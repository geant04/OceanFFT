// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "Custom/Ocean"
{
    Properties
    {
        _Color ("Color", Color) = (0.14, 0.61, 0.690,1)
        _Ambient ("Ambient Color", Color) = (0.15, 0.675, 0.716, 1)
        _SunColor ("Sun Color", Color) = (0.93, 0.93, 0.78,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
        _SunThreshold ("Sun Threshold", Range(-100, 100)) = 0.0
        _Range ("Range", Range(0,1)) = 0.001
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
            float3 worldPos : TEXCOORD2;
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
            float lambda = 1.0;

            //float h = 0.5 * sin(v.vertex.x + v.vertex.y + _Time.y * 1.0);
            float3 vertexPosition = v.vertex.xyz;
            float3 o = vertexPosition;

            float3 worldPos = mul(unity_ObjectToWorld, v.vertex);
            
            float4 displacementData = tex2Dlod(_DisplacementTexture, float4(worldPos.xz * _Range, 0.0, 0.0));

            i.vertex = UnityObjectToClipPos(vertexPosition + displacementData.xyz * 2.5);
            i.uv = worldPos.xz;
            //i.uv = v.uv;
            i.worldPos = mul(unity_ObjectToWorld, o);
            i.viewDir = WorldSpaceViewDir(v.vertex);

            return i;
        }

        float4 fp(v2f i) : SV_TARGET {
            float2 uv = i.uv;
            
            float4 displacementData = tex2Dlod(_SlopeTexture, float4(uv * _Range, 0.0, 0.0));
            float4 normalData = tex2Dlod(_SlopeTexture, float4(uv * _Range, 0.0, 0.0));
            float3 normal = normalize(normalData.xyz) * 0.10;
            float3 viewDir = normalize(i.viewDir);

            float3 lightVector = normalize(_WorldSpaceLightPos0);
            float diffuse = max(dot(normal, lightVector), 0.0);

            float4 normalColor = _Color * _Ambient * lerp(_Color, _Ambient, displacementData.g + 0.40);

            float3 reflectionVector = reflect(-viewDir, normal);
            half4 skyData = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectionVector + 0.05);

            half reflectionFactor = max(dot(viewDir, normal), 0.0);
            //float4 reflectionColor = float4(lerp(normalColor, skyData.xyz, reflectionFactor), 0.0);
            
            float3 halfwayDir = normalize(_WorldSpaceLightPos0 + viewDir);
            float spec = pow(max(dot(normalize(normal + displacementData.xyz), halfwayDir), 0.0), 128.0);
            float4 specColor = _LightColor0 * spec;
            //specColor.a = (specColor.a > 0.98 + _SunThreshold * 0.02);

            //float4 specColor = max(0, dot(_WorldSpaceLightPos0.xyz, reflect(-viewDir.xzy, normal.xzy))) * _LightColor0;
            //specColor.a = (specColor.a > 0.98 + _SunThreshold * 0.02);

            float4 waterReflective = float4(0.02, 0.02, 0.02, 1.0);
            float power = 0.4;
            float4 fresnel_schlick = power * skyData * (waterReflective + (1 - waterReflective) * pow(1 - dot(normal.xzy * 0.40, halfwayDir.xzy), 2));
            
            return normalColor + (specColor * 0.02) + fresnel_schlick;
            //return float4(displacementData.g * 5.0, 0.0, 0.0, 0.0);
            //return displacementData;
        }

        ENDCG
        }
    }
    FallBack "Diffuse"
}
