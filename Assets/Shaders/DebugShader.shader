Shader "Custom/DebugShader"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
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

        sampler2D _DisplacementTexture;

        v2f vp(VertexData v) {
            v2f i;

            float3 localVertex = v.vertex.xyz;
            float heightData = tex2Dlod(_DisplacementTexture, float4(v.uv, 0, 0)).r;
            localVertex.y += heightData;
            localVertex.y *= 100;
            localVertex.y -= 7;

            float3 worldPos = mul(unity_ObjectToWorld, localVertex);

            i.vertex = UnityObjectToClipPos(localVertex);
            i.uv = v.uv;
            i.viewDir = WorldSpaceViewDir(v.vertex);

            return i;
        }

        float4 fp(v2f i) : SV_TARGET{
            float2 uv = i.uv;
            float4 data = tex2D(_DisplacementTexture, uv) * 24 - 1.25;
            float testValue = data.a / 256;

            //return float4(testValue, 0, 0, 1);
            //return float4(data);
            return float4(data.r * 1, data.g, data.b, data.a);
        }

        ENDCG
        }
    }
    FallBack "Diffuse"
}
