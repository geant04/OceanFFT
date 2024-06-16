// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "Custom/Ocean"
{
    Properties
    {
        // darker green colors
        _ScatterColor ("Scatter Color", Color) = (0.2893081, 0.8702705, 1.0,1)
        _BubbleColor ("Bubble Color", Color) = (0.1507654, 0.1779208, 0.1981132, 1)
        _SunColor ("Sun Color", Color) = (1.0, 0.8825995, 0.5157232,1)

        // fun parameters for tweaking
        _Range("Range", Range(0,1)) = 0.642
        _Bias("Height Bias", Range(0,1)) = 0
        _k1 ("Height Scatter Strength", Range(0,1)) = 0.212
        _k2 ("Light Reflectance", Range(0, 1)) = 0.273
        _k3 ("Lambert bias", Range(0,1)) = 0.153
        _pf ("Bubble density", Range(0,1)) = 0.118
    }
    SubShader
    {
        Pass {

        CGPROGRAM
        // Physically based Standard lighting model, and enable shadows on all light types
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

        #pragma vertex vp
        #pragma fragment fp
        #include "UnityCG.cginc"
        #include "Lighting.cginc"

        int _L, _N;

        float4 _ScatterColor, _BubbleColor, _SunColor;
        float _SunThreshold, _Range, _Bias;
        float _k1, _k2, _k3, _pf;

        sampler2D _DisplacementTexture, _SlopeTexture;

        //UNITY_DECLARE_TEX2DARRAY(_TestTexture);

        v2f vp(VertexData v) {
            v2f i;

            //float h = 0.5 * sin(v.vertex.x + v.vertex.y + _Time.y * 1.0);
            float3 vertexPosition = v.vertex.xyz;
            float3 worldPos = mul(unity_ObjectToWorld, v.vertex);

            float2 uv = worldPos.xz;
            
            float4 displacementData0 = tex2Dlod(_DisplacementTexture, float4(uv * pow(_Range, 10.0), 0.0, 0.0));
            float4 displacementData1 = tex2Dlod(_DisplacementTexture, float4(uv * pow(_Range, 4.0), 0.0, 0.0));
            float4 displacementData2 = tex2Dlod(_DisplacementTexture, float4(uv * pow(_Range, 12.0), 0.0, 0.0));

            float4 totalDisplacement = displacementData0 + displacementData1 * 0.20 + displacementData2 * 1.25;

            float k = length(ObjSpaceViewDir(v.vertex));

            i.vertex = UnityObjectToClipPos(vertexPosition + totalDisplacement.xyz * float3(1, 4.0 *_Bias + 1.0, 1));
            i.uv = uv;
            i.viewDir = WorldSpaceViewDir(v.vertex);
            i.worldPos = float4(worldPos, k);

            return i;
        }

        // from the beautiful Atlas presentation
        float3 L_Scatter(float3 wi, float3 wo, float3 wh, float h) {
            // in a way, H is like the ambience... or something like that
            float H = max(0, h) * 2.0;
            float hTerm = _k1 * H * pow(max(dot(wo, -wi), 0.0), 4.0);
            float halfLamb = pow(0.5 - 0.5 * max(dot(wi, wh), 0.0), 1.0);
            float refl = _k2 * pow(max(dot(wo, wh), 0.0), 2.0);

            float lambert = _k3 * max(dot(wh, wi), 0.0);
            // (hTerm * halfLamb) = attenuation?
            float3 lo = (hTerm * halfLamb + refl) * _ScatterColor * _SunColor;
            lo += lambert * _ScatterColor * _SunColor + _pf * _BubbleColor * _SunColor;

            return lo;
        }

        float3 fresnelSchlicK(float3 theta) {
            float eta = 1.33f;
            float R = ((eta - 1) * (eta - 1)) / ((eta + 1) * (eta + 1));

            // note that there is no metallicness, we will resort to vec3(0.02) thx mally
            R = 0.04;
            return R + (1 - R) * pow(1.f - theta, 5.0f);
        }


        float4 fp(v2f i) : SV_TARGET{
            float2 uv = i.worldPos.xz;

            float4 displacementData0 = tex2Dlod(_DisplacementTexture, float4(uv * pow(_Range, 10.0), 0.0, 0.0));
            float4 displacementData1 = tex2Dlod(_DisplacementTexture, float4(uv * pow(_Range, 4.0), 0.0, 0.0));
            float4 displacementData2 = tex2Dlod(_DisplacementTexture, float4(uv * pow(_Range, 12.0), 0.0, 0.0));

            float4 displacementData = displacementData0 + displacementData1 * 0.20 + displacementData2 * 1.25;

            float4 normalData0 = tex2D(_SlopeTexture, float4(uv * pow(_Range, 10.0), 0.0, 0.0));
            float4 normalData1 = tex2D(_SlopeTexture, float4(uv * pow(_Range, 4.0), 0.0, 0.0));
            float4 normalData2 = tex2D(_SlopeTexture, float4(uv * pow(_Range, 12.0), 0.0, 0.0));

            float4 normalData = normalData0 + normalData1 * 0.20 + normalData2 * 1.25;

            float3 normal = normalize(float3(-normalData.x, 1.0f, -normalData.y));
            normal = normalize(UnityObjectToWorldNormal(normalize(normal)));

            float3 wo = normalize(i.viewDir);
            float3 wi = normalize(_WorldSpaceLightPos0);
            float3 wh = normalize(wo + normal);

            
            float3 l_sctr = L_Scatter(wi, wo, wh, displacementData.r * (_Bias * 4.0 + 1.0));

            float3 F = fresnelSchlicK(max(dot(wh * 0.75, wo), 0.0));
            float3 fresNor = (normal + float3(0.0, 2.5, 0.0)) * 0.50;
            float3 refl = normalize(reflect(-wo, fresNor));
            float3 env_irradiance = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, refl);
            float3 lo_env = F * env_irradiance * 10.0;

            float3 spec = pow(max(dot(normal, normalize(wo + wi)), 0.0), 160.0);
            float3 lo_sun = _LightColor0.xyz * spec * 0.80;

            float foam = displacementData.w;

            if (foam < 0.80) {
                foam = 0;
            }
            else {
                foam = pow(foam, 4.0) * 0.60;
                foam = min(1.0, foam);
            }

            float3 lo = (1 - F) * l_sctr + lo_sun + lo_env;
            lo = lerp(lo, float3(1.0, 1.0, 1.0), foam * 0.15);

            float dist = i.worldPos.w / 150.0;
            float density = 1.5;
            dist = pow(2, -1.0 * pow(dist * density, 2.0));
            dist = 1.0 - dist;

            // fake the fog baby
            lo = lerp(lo, float3(1.0, 1.0, 1.0), dist);

            return float4(lo, 1.0);
            // 0.10 for darker
        }

        ENDCG
        }
    }
    FallBack "Diffuse"
}
