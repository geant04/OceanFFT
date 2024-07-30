Shader "Custom/SkyShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _TimeOfDay("Time of Day", Range(0,1)) = 1.0
    }
    SubShader
    {
        Tags { "RenderType" = "Background" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"
            #include "Assets/Shaders/SkyFunctions.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
                float4 worldPos: TEXCOORD1;
                float2 screenPos : TEXCOORD2;
                float3 viewDir : COLOR;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float _TimeOfDay;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                o.viewDir = WorldSpaceViewDir(float4(v.vertex.xyz, 1.0));
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float4 wo = normalize(i.worldPos);
                float3 wi = _WorldSpaceLightPos0;
                float3 color = GetSkyColor(wo, wi);

                return float4(color, 1.0);
            }
            ENDCG
        }
    }
}
