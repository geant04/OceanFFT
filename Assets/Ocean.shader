// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "Custom/Ocean"
{
    Properties
    {
        // darker green colors
        _Color ("Color", Color) = (0.21, 0.85, 0.84,1)
        _Ambient ("Ambient Color", Color) = (0.11, 0.70, 0.75, 1)
        _SunColor ("Sun Color", Color) = (0.93, 0.93, 0.78,1)

        /* brighter green colors
        _Color ("Color", Color) = (0.26, 1, 0.98,1)
        _Ambient ("Ambient Color", Color) = (0.35, 0.84, 0.89, 1)
        _SunColor ("Sun Color", Color) = (0.93, 0.93, 0.78,1)
        */

        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
        _SunThreshold ("Sun Threshold", Range(-100, 100)) = 0.0
        _Range ("Range", Range(0,1)) = 0.004
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
        };

        #pragma vertex vp
        #pragma fragment fp
        #include "UnityCG.cginc"
        #include "Lighting.cginc"

        int _L, _N;

        float4 _Color, _Ambient, _SunColor;
        float _SunThreshold, _Range;

        sampler2D _DisplacementTexture, _SlopeTexture;

        //UNITY_DECLARE_TEX2DARRAY(_TestTexture);

        v2f vp(VertexData v) {
            v2f i;
            float lambda = 0.001;

            //float h = 0.5 * sin(v.vertex.x + v.vertex.y + _Time.y * 1.0);
            float3 vertexPosition = v.vertex.xyz;
            float3 worldPos = mul(unity_ObjectToWorld, v.vertex);
            
            float4 displacementData = tex2Dlod(_DisplacementTexture, float4(worldPos.xz * _Range, 0.0, 0.0));
            float4 displacementData2 = tex2Dlod(_DisplacementTexture, float4(worldPos.xz * _Range * 0.15, 0.0, 0.0));

            float4 totalDisplacement = displacementData * 0.4 + displacementData2 * 2.0;

            i.vertex = UnityObjectToClipPos(vertexPosition + totalDisplacement.xyz * float3(1, 0.8, 1));
            i.uv = worldPos.xz;
            //i.uv = v.uv;
            i.viewDir = WorldSpaceViewDir(v.vertex);

            return i;
        }

        float4 fp(v2f i) : SV_TARGET {
            float2 uv = i.uv;
            
            float4 displacementData = tex2Dlod(_DisplacementTexture, float4(uv * _Range, 0.0, 0.0));
            float4 displacementData2 = tex2Dlod(_DisplacementTexture, float4(uv * _Range * 0.05, 0.0, 0.0));

            displacementData = displacementData + displacementData2 * 1.0;

            float4 normalData = tex2Dlod(_SlopeTexture, float4(uv * _Range, 0.0, 0.0));
            float4 normalData2 = tex2Dlod(_SlopeTexture, float4(uv * _Range * 0.25, 0.0, 0.0));

            normalData = normalData + normalData2 * 1.5;

            float3 normal = normalize(float3(-normalData.x, 1.0f, -normalData.y));
            normal = normalize(UnityObjectToWorldNormal(normalize(normal))) * 0.40;

            float3 viewDir = normalize(i.viewDir);

            float3 lightVector = normalize(_WorldSpaceLightPos0);
            float diffuse = max(dot(normal, lightVector), 0.0);

            //float4 normalColor = _Color * diffuse;

            float3 reflectionVector = reflect(-viewDir, normal);
            half4 skyData = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectionVector + 0.02);

            float4 normalColor = _Color * (_Ambient + diffuse) * lerp(_Ambient, _Color, displacementData.g * 2.0 + diffuse);
            
            float3 halfwayDir = normalize(_WorldSpaceLightPos0 + viewDir);
            float spec = pow(max(dot(normalize(normal), halfwayDir * 1.15), 0.0), 64.0);
            float4 specColor = _LightColor0 * spec * 0.006;

            float4 waterReflective = float4(0.02, 0.02, 0.02, 1.0);
            float power = 0.70;
            float3 fresnelNormal = normalize(normal * float3(1, 1.0, 1));

            float4 fresnel_schlick = power * skyData * (waterReflective + (1 - waterReflective) * pow(1 - max(dot(viewDir, fresnelNormal * 0.8), 0.0), 5.0f));
            
            return normalColor * 0.35 + (specColor * 0.001) + fresnel_schlick;
            // 0.10 for darker
        }

        ENDCG
        }
    }
    FallBack "Diffuse"
}
