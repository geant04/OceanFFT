Shader "Custom/DebugShader"
{
    Properties
    {
        // darker green colors
        _ScatterColor("Scatter Color", Color) = (0.81761, 0.9982171, 1.0,1)
        _BubbleColor("Bubble Color", Color) = (0.01370592, 0.1456759, 0.1792453, 1)
        _SunColor("Sun Color", Color) = (1.0, 1.0, 1.0, 1)

        // fun parameters for tweaking
        _Range("Range", Range(0,1)) = 0.642
        _Bias("Height Bias", Range(0,1)) = 0
        _k1("Height Scatter Strength", Range(0,1)) = 0.546
        _k2("Light Reflectance", Range(0, 1)) = 0.074
        _k3("Lambert bias", Range(0,1)) = 0.146
        _pf("Bubble density", Range(0,1)) = 0.566
    }
    SubShader
    {
        Pass
        {

        CGPROGRAM

        struct VertexData {
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
        };

        struct v2f {
            float4 vertex : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 viewDir : COLOR;
        };

        #pragma vertex vp;
        #pragma fragment fp;
        #include "UnityCG.cginc"
        #include "Lighting.cginc"

        sampler2D _DisplacementTexture;
        float _N;
        float _TileSize;
        float _TimeOfDay; // float ranging from 0-1

        float4 _ScatterColor, _BubbleColor, _SunColor;
        float _SunThreshold, _Range, _Bias;
        float _k1, _k2, _k3, _pf;

        v2f vp(VertexData v) 
        {
            v2f i;

            float3 localVertex = v.vertex.xyz;
            float3 worldPos = mul(unity_ObjectToWorld, float4(localVertex, 1.0));
            i.uv = worldPos.xz / _TileSize;

            float heightData = tex2Dlod(_DisplacementTexture, float4(i.uv, 0, 0)).r;
            localVertex.y += heightData;
            localVertex.y *= 100;
            localVertex.y -= 0;

            i.vertex = UnityObjectToClipPos(localVertex);
            i.viewDir = WorldSpaceViewDir(float4(localVertex, 1.0));

            return i;
        }

        float3 getNormal(float2 uv)
        {
            // https://web.archive.org/web/20101129095145/http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.161.8979&rep=rep1&type=pdf
            float texelSize = 1.0 / 256.0;
            float texelAspect = 512;

            // experiment with calculating the normal in the shader; might be super slow
            float4 h;
            h.x = texelAspect * tex2D(_DisplacementTexture, uv + texelSize * float2(0, -1)).r;
            h.y = texelAspect * tex2D(_DisplacementTexture, uv + texelSize * float2(-1, 0)).r;
            h.z = texelAspect * tex2D(_DisplacementTexture, uv + texelSize * float2(1, 0)).r;
            h.w = texelAspect * tex2D(_DisplacementTexture, uv + texelSize * float2(0, 1)).r;

            float3 n;
            n.z = h.w - h.x;
            n.x = h.y - h.z;
            n.y = 2.0;

            return normalize(n);
        }

        // from the beautiful Atlas presentation
        float3 L_Scatter(float3 wi, float3 wo, float3 wh, float h) 
        {
            float H = max(0, h) * 2.0;
            float hTerm = _k1 * H * pow(max(dot(wo, -wi), 0.0), 4.0);
            float halfLamb = pow(0.5 - 0.5 * max(dot(wi, wh), 0.0), 1.0);
            float refl = _k2 * pow(max(dot(wo, wh), 0.0), 2.0);

            float lambert = _k3 * max(dot(wh, wi), 0.0);
            float3 lo = (hTerm * halfLamb + refl) * _ScatterColor * _LightColor0;
            lo += lambert * _ScatterColor * _SunColor + _pf * _BubbleColor * _LightColor0;

            return lo;
        }

        float3 FresnelSchlick(float3 theta) 
        {
            float3 F0 = 0.02;
            return F0 + (1 - F0) * pow(1.f - theta, 5.0f);
        }

        float pdf(float2 xy) {
            // ??? this some magic fr
        }

        // Approximation for masking and shadowing
        float WalterSmith(float3 w)
        {

        }

        // https://jcgt.org/published/0003/02/03/paper.pdf page 37
        float GeometrySmithMasking(float3 wo, float3 wi) {
            // this is supposed to be some masking/shadowing term, will get into it when i eventually get to it in the atlas talk

        }

        float cosGradient(float dcOffset, float amp, float freq, float phase, float x)
        {
            float TAU = 6.2831853071795862;
            return clamp((dcOffset + amp * cos(TAU * (phase + freq * x))), 0., 1.);
        }

        float3 GetSkyColor(float timeOfDay, float altitude)
        {
            float middleDay = 0.8 * pow(cos(2.0 * (timeOfDay - 0.9)), 4.0) + 0.2;
            float x = timeOfDay;

            float mR = cosGradient(0.4384, 1.0984, 0.4184, -1.310, x);
            float mG = cosGradient(0.5084, 0.9874, 0.5984, -1.481, x);
            float mB = cosGradient(0.7284, -0.391, -0.551, 0.1884, x);

            float3 botColor = lerp(float3(0.0, 0.0, 0.0), float3(1.0, 1.0, 1.0), timeOfDay);
            float3 midColor = float3(mR, mG, mB);
            float3 topColor = lerp(float3(0.0, 0.0, 0.0), float3(0.6, 0.8, 0.92), timeOfDay);

            float powStrength = 2.0;

            float topStrength = pow(altitude, powStrength);
            float botStrength = pow(1.0 - altitude, powStrength);

            topColor;
            botColor *= botStrength;

            float midAltPow = 1.0 - clamp(2.3 * topStrength + 1.35 * botStrength, 0.0, 1.0);
            //midColor midAltPow;

            float balanceFunc = 2.0 * pow(cos(1.2 * altitude - 1.5), 4.0) + 0.3;
            balanceFunc = clamp(balanceFunc, 0, 1);

            float3 skyColor = lerp(midColor, topColor, 1.0 - altitude);

            return skyColor;
        }

        float3 sampleSky(float3 r)
        {
            float3 normR = normalize(0.50 * r + 0.50);
            float alt = 1.0 - clamp(dot(normR, float3(0, 1.0, 0)), 0, 1);

            float3 skyColor = GetSkyColor(1, alt);
            return normR;
        }

        float4 fp(v2f i) : SV_TARGET
        {
            float2 uv = i.uv;

            // resolution = 256
            // ocean size = patch size? or something??
            float3 normal = getNormal(i.uv);

            // height sample
            float4 dy = tex2D(_DisplacementTexture, uv).r * 10;

            // actual stuff
            float3 wo = normalize(-i.viewDir);
            float3 wi = normalize(_WorldSpaceLightPos0);
            float3 wh = normalize(-wo + normal);

            //if (dot(normal, wo) < 0) normal = -normal;

            // Ambient diffuse + subsurface scattering lighting
            float3 sctrNor = normal;
            float3 sctrWh = normalize(-wo + sctrNor);
            float3 l_sctr = L_Scatter(wi, -wo, sctrWh, dy);

            // Environment reflections / glossy -- non PBR
            float3 fresNor = normal;
            float3 fresWh = normalize(wo + fresNor);
            float3 F = FresnelSchlick(abs(dot(fresWh, wo)));
            F = pow(1.0 - abs(dot(normal, wo)), 5.0);

            float3 reflNor = normalize(normal);
            float3 refl = normalize(reflect(wo, reflNor));
            float3 env_irradiance = sampleSky(refl);
            float3 lo_env = env_irradiance;
             
            // Additional specular highlights from the sun
            wh = normalize(-wo + wi);
            float3 spec = pow(abs(dot(normal, wh)), 128.0);
            float3 lo_sun = _LightColor0.xyz * spec * 1.0;

            wo = -wo;
            //wh = normalize(wo + wi);
            float3 loSunNum = _LightColor0.xyz * FresnelSchlick(max(dot(wh, wi), 0));
            //float3 loSunDenom = 4 * max(dot(float3(0, 0, 1), wo)); // masking and shadowing

            // Additional variable naming for organization
            float3 kd = (1 - F) * l_sctr; // diffuse
            float3 ks = F * lo_env + F * lo_sun; // does lo_sun need * F to be physically accurate?

            float3 lo = kd + ks;
            
            return float4(lo, 1.0);
        }

        ENDCG
        }
    }
    FallBack "Diffuse"
}
