Shader "Custom/OceanShader"
{
    Properties
    {
        // darker green colors
        _ScatterColor("Scatter Color", Color) = (0.6855345, 0.8911644, 1.0,1)
        _BubbleColor("Bubble Color", Color) = (0.03512517, 0.2297952, 0.3490566, 1)
        _SunColor("Sun Color", Color) = (1.0, 1.0, 1.0, 1)

        // fun parameters for tweaking
        _Range("Range", Range(0,1)) = 0.642
        _Bias("Height Bias", Range(0,1)) = 0
        _k1("Height Scatter Strength", Range(0,1)) = 0.6
        _k2("Light Reflectance", Range(0, 1)) = 0.1
        _k3("Lambert bias", Range(0,1)) = 0.146
        _pf("Bubble density", Range(0,1)) = 0.11

        _t("T", Range(0,1)) = 0.566
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
            float4 worldPos : TEXCOORD1;
        };

        #pragma vertex vp;
        #pragma fragment fp;
        #include "UnityCG.cginc"
        #include "Lighting.cginc"
        #include "Assets/Shaders/SkyFunctions.hlsl"


        sampler2D _DisplacementTexture0;
        sampler2D _DisplacementTexture1;
        sampler2D _NormalTexture0;

        float _N0;
        float _N1;

        float _N;
        float _TileSize;
        float _TimeOfDay; // float ranging from 0-1
        float _t0, _t1;
        float _d0Scale;
        float _d1Scale;

        float4 _ScatterColor, _BubbleColor, _SunColor;
        float _SunThreshold, _Range, _Bias;
        float _k1, _k2, _k3, _pf;

        v2f vp(VertexData v) 
        {
            v2f i;

            float3 localVertex = v.vertex.xyz;
            float4 worldPos = mul(unity_ObjectToWorld, float4(localVertex, 1.0));
            i.uv = worldPos.xz / _TileSize * _d0Scale;

            // convert from 0-1 to -1 to 1?
            float4 dydxdz = tex2Dlod(_DisplacementTexture0, float4(i.uv, 0, 0));

            localVertex.y = 1;
            localVertex.y *= dydxdz.r;
            localVertex.x += dydxdz.g;
            localVertex.z += dydxdz.b;
            localVertex.y -= 0.025; // adjustable parameter
            //localVertex = v.vertex.xyz;

            i.vertex = UnityObjectToClipPos(localVertex);
            i.viewDir = WorldSpaceViewDir(float4(localVertex, 1.0));
            i.worldPos = worldPos;

            return i;
        }

        float3 GetDisplacement(sampler2D tex, float2 uv)
        {
            float4 displacement = tex2D(tex, uv);
            return float3(displacement.b, displacement.r, displacement.b);
        }

        float2 uvCoord(float2 uv, float texelSize, float dir)
        {
            float2 uvNew = uv + texelSize * dir;
            //uvNew.x = clamp(uvNew.x, 0, 1);
            //uvNew.y = clamp(uvNew.y, 0, 1);
            return uvNew;
        }

        float3 getNormal(sampler2D tex, float2 uv)
        {
            // https://web.archive.org/web/20101129095145/http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.161.8979&rep=rep1&type=pdf
            float texel = 1.0 / 512.0;
            float texelSize = 1.0 / 512.0;

            float3 center = GetDisplacement(tex, uv);
            float3 right = GetDisplacement(tex, uvCoord(uv, texel, float2(1, 0))) - center + float3(texelSize, 0, 0);
            float3 left = GetDisplacement(tex, uvCoord(uv, texel, float2(-1, 0))) - center + float3(-texelSize, 0, 0);
            float3 top = GetDisplacement(tex, uvCoord(uv, texel, float2(0, -1))) - center + float3(0, 0, -texelSize);
            float3 bottom = GetDisplacement(tex, uvCoord(uv, texel, float2(0, 1))) - center + float3(0, 0, texelSize);

            float3 topRight = cross(right, top);
            float3 topLeft = cross(top, left);
            float3 bottomLeft = cross(left, bottom);
            float3 bottomRight = cross(bottom, right);

            float3 normal = normalize(topRight + topLeft + bottomRight + bottomLeft);
            
            return normal;
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

        // Different SSS approach
        float3 L_Scatter2(float3 wi, float3 wo, float3 n, float dy)
        {
            float distortion = 1.0;
            float power = 1.5;
            float scale = 5.0;
            float attenuation = _k2 * pow(max(dot(wo, normalize(n -wi)), 0.0), 2.0);

            float3 wh = normalize(wi + n * distortion);
            float vdotH = pow(saturate(dot(wo, -wh)), power) * scale; // angle from view to normal + distortion

            float h = 20.0 * dy;
            float thickness = _k1 * h * pow(max(dot(wo, -wi), 0.0), 4.0);

            float3 lo = attenuation * (vdotH * _ScatterColor) * thickness;
            lo = _ScatterColor * _LightColor0 * lo;
            lo += _pf * _BubbleColor * _LightColor0;

            return lo;
        }

        float3 FresnelSchlick(float3 theta) 
        {
            float3 F0 = 0.04;
            return F0 + (1 - F0) * pow(1.0 - theta, 5.0f);
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

        float3 sampleSky(float3 wo, float3 wi)
        {
            return GetSkyColor(wo, wi);
        }

        float4 fp(v2f i) : SV_TARGET
        {
            float2 uv = i.uv;

            // resolution = 256
            // ocean size = patch size? or something??
            float3 normal =
                _t0 * getNormal(_DisplacementTexture0, i.uv * _d0Scale);
                + _t1 * getNormal(_DisplacementTexture1, i.uv * _d1Scale);

            normal = normalize(normal);

            //normal = normalize(float3(normal.x, 1.0f, normal.b));
            //normal = normalize(UnityObjectToWorldNormal(normalize(normal)));

            //normal = normalize(float3(-normal.x, 1.0f, -normal.y));
            //return float4(normal.r, 0, normal.b, 1.0);
            
            float2 dy = 
                _t0 * tex2Dlod(_DisplacementTexture0, float4(i.uv * _d0Scale, 0, 0)).rb
                + _t1 * tex2Dlod(_DisplacementTexture1, float4(i.uv * _d1Scale, 0, 0)).rb;

            float2 dyTest = float2(_t0 * tex2Dlod(_DisplacementTexture0, float4(i.uv * _d0Scale, 0, 0)).r,
                _t1 * tex2Dlod(_DisplacementTexture1, float4(i.uv * _d1Scale, 0, 0)).r);

            float4 dydxdz = tex2Dlod(_DisplacementTexture0, float4(i.uv, 0, 0));
            float4 nxnynz = tex2Dlod(_NormalTexture0, float4(i.uv, 0, 0));


            normal = normalize(nxnynz.rgb);

            // actual stuff
            float3 wo = normalize(-i.viewDir);
            float3 wi = normalize((_WorldSpaceLightPos0));
            float3 wh = normalize(-wo + normal);

            //if (dot(normal, wo) < 0) normal = -normal;

            // Ambient diffuse + subsurface scattering lighting
            float3 sctrNor = normal;
            float3 sctrWh = normalize(-wo + sctrNor);
            float3 l_sctr = L_Scatter(wi, -wo, sctrWh, dydxdz.r * 15.0 + 0.01);

            // Environment reflections / glossy -- non PBR
            float3 fresWh = normalize(wo + normal);
            float fresTheta = max(dot(0.92f * fresWh, wo), 0.0);
            float3 F = FresnelSchlick(1.0f - fresTheta);

            float3 reflNor = normalize(normal);
            float3 refl = normalize(reflect(wo, reflNor));
            float3 env_irradiance = GetSkyColorFromOcean(refl, wi);
            float3 lo_env = env_irradiance * 0.55f;
             
            // Additional specular highlights from the sun
            wh = normalize(-wo + wi);
            float3 spec = pow(abs(dot(-normal, wh)), 128.0);
            float3 lo_sun = _LightColor0.xyz * spec * 4.0;

            // Additional variable naming for organization
            float3 lo = (1 - F) * l_sctr + F * (lo_sun + lo_env);

            return float4(lo, 1.0);
        }

        ENDCG
        }
    }
    FallBack "Diffuse"
}
