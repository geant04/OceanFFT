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

            float3 worldPos = mul(unity_ObjectToWorld, v.vertex);

            i.vertex = UnityObjectToClipPos(v.vertex.xyz);
            i.uv = v.uv;
            i.viewDir = WorldSpaceViewDir(v.vertex);

            return i;
        }

        float4 fp(v2f i) : SV_TARGET{
            float2 uv = i.uv;
            float4 data = tex2D(_DisplacementTexture, uv);
            
            return float4(data.r * 100000, data.g, data.b, data.a);
        }

        ENDCG
        }
    }
    FallBack "Diffuse"
}
