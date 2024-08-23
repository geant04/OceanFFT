Shader "Custom/OceanShader"
{
    Properties
    {
        // darker green colors
        _ScatterColor("Scatter Color", Color) = (0.7610062, 0.9648539, 1.0,1)
        _BubbleColor("Bubble Color", Color) = (0.7893081, 0.9209905, 0.9959149, 1)
        _SunColor("Sun Color", Color) = (1.0, 1.0, 1.0, 1)

        // fun parameters for tweaking
        _Range("Range", Range(0,1)) = 0.642
        _Bias("Height Bias", Range(0,1)) = 0
        _k1("Height Scatter Strength", Range(0,1)) = 0.6
        _k2("Light Reflectance", Range(0, 1)) = 0.1
        _k3("Lambert bias", Range(0,1)) = 0.146
        _pf("Bubble density", Range(0,1)) = 0.14

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
        sampler2D _CameraDepthTexture;

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
            localVertex.x += dydxdz.g * 16.0;
            localVertex.z += dydxdz.b * 16.0;
            localVertex.y -= 0.025; // adjustable parameter
            //localVertex = v.vertex.xyz;

            i.vertex = UnityObjectToClipPos(localVertex);
            i.viewDir = WorldSpaceViewDir(float4(v.vertex.xyz, 1.0));
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

        float3 L_Scatter(float3 wi, float3 wo, float3 wh, float h) {
            // in a way, H is like the ambience... or something like that
            float H = max(0, h) * 2.0;
            float hTerm = _k1 * H * pow(max(dot(wo, -wi), 0.0), 4.0);
            float halfLamb = pow(0.5 - 0.5 * max(dot(wi, wh), 0.0), 1.0);
            float refl = _k2 * pow(max(dot(wo, wh), 0.0), 2.0);

            float3 SunColor = _LightColor0 * 0.30;
            float lambert = _k3 * max(dot(wh, wi), 0.0);
            float3 lo = (hTerm * halfLamb + refl) * _ScatterColor * SunColor;
            lo += lambert * _ScatterColor * SunColor + _pf * _BubbleColor * SunColor;

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
            
            float2 dy = 
                _t0 * tex2Dlod(_DisplacementTexture0, float4(i.uv * _d0Scale, 0, 0)).rb
                + _t1 * tex2Dlod(_DisplacementTexture1, float4(i.uv * _d1Scale, 0, 0)).rb;

            float2 dyTest = float2(_t0 * tex2Dlod(_DisplacementTexture0, float4(i.uv * _d0Scale, 0, 0)).r,
                _t1 * tex2Dlod(_DisplacementTexture1, float4(i.uv * _d1Scale, 0, 0)).r);

            float4 dydxdz = tex2Dlod(_DisplacementTexture0, float4(i.uv, 0, 0));
            float4 nxnynz = tex2Dlod(_NormalTexture0, float4(i.uv, 0, 0));


            normal = normalize(nxnynz.rgb);
            //normal = normalize(UnityObjectToWorldNormal(normalize(normal)));

            // actual stuff
            float3 wo = normalize(-i.viewDir);
            //if (dot(normal, wo) < 0) normal = -normal;

            float3 wi = normalize((_WorldSpaceLightPos0));
            float3 wh = normalize(-wo + normal);


            // Ambient diffuse + subsurface scattering lighting
            float3 sctrNor = normal;
            float3 sctrWh = normalize(-wo + sctrNor);
            float3 l_sctr = L_Scatter(wi, -wo, sctrWh, dydxdz.r * (20.9) + 0.07);

            // Environment reflections / glossy -- non PBR
            float3 fresWh = normalize(wo + normal);
            float fresTheta = max(dot(0.75 * fresWh, wo), 0.0);
            float3 F = FresnelSchlick(fresTheta);

            float3 reflNor = (normal + float3(0.0, 2.5, 0.0)) * 0.50;
            float3 refl = normalize(reflect(wo, reflNor));
            float3 env_irradiance = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, refl);
                //GetSkyColorFromOcean(refl, wi);
            float3 lo_env = env_irradiance * 3.0;
             
            // Additional specular highlights from the sun
            wh = normalize(-wo + wi);
            float3 spec = pow(abs(dot(normal, wh)), 128.0);
            float3 lo_sun = _LightColor0.xyz * spec * 2.0;

            // Additional variable naming for organization
            float3 lo = (1 - F) * l_sctr + F * (lo_sun + lo_env);


            float dist = length(i.worldPos - _WorldSpaceCameraPos) / 150.0;

            float density = 1.0;
            dist = pow(2, -1.0 * pow(dist * density, 2.0));
            dist = 1.0 - dist;

            lo = lerp(lo, float3(1.0, 1.0, 1.0), dist);

            return float4(lo, 1.0);
        }

        ENDCG
        }
    }
    FallBack "Diffuse"
}
