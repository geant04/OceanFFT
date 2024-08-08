Shader "Custom/FogShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "Assets/Shaders/SkyFunctions.hlsl"

            float _FogStart = 20;
            float _FogEnd = 90;
            float4x4 _InverseViewProjection;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float3 UVToViewDir(float2 uv, float depth)
            {
                float2 ndc = uv * 2.0 - 1.0;
                float4 p = float4(ndc.xy, 1, 1);
                p = mul(unity_CameraInvProjection, p);
                return normalize(_WorldSpaceCameraPos - p.xyz);
            }

            sampler2D _MainTex;
            sampler2D _CameraDepthTexture;

            fixed4 frag (v2f i) : SV_Target
            {
                float4 sceneColor = tex2D(_MainTex, i.uv);

                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
                float sceneZ = LinearEyeDepth(depth);

                float fogFactor = saturate((sceneZ - 20.0) / (50.0));
                float4 fogColor = lerp(0.5, 1.0, fogFactor);

                float3 viewDir = UVToViewDir(i.uv, depth);
                float3 wi = normalize(_WorldSpaceLightPos0.xyz);
                float3 skyColor = GetSkyColor(viewDir, wi);

                float3 preSceneColor = lerp(sceneColor, fogColor, fogFactor).xyz;
                float3 finalLerpedColor = lerp(preSceneColor, skyColor, fogFactor);

                return float4(finalLerpedColor, 1.0);
            }
            ENDCG
        }
    }
}
