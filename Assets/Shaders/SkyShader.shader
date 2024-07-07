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
                return o;
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

                float3 botColor = lerp(float3( 0.0, 0.0, 0.0 ), float3( 1.0, 1.0, 1.0), timeOfDay);
                float3 midColor = float3(mR, mG, mB);
                float3 topColor = lerp(float3( 0.0, 0.0, 0.0), float3( 0.6, 0.8, 0.92 ), timeOfDay);

                float powStrength = 2.0;
                
                float topStrength = pow(altitude, powStrength);
                float botStrength = pow(1.0 - altitude, powStrength);

                topColor;
                botColor *= botStrength;

                float midAltPow = 1.0 - clamp(2.3 * topStrength + 1.35 * botStrength, 0.0, 1.0);
                //midColor midAltPow;

                float balanceFunc = 2.0 * pow(cos(1.2 * altitude - 1.5), 4.0) + 0.3;
                balanceFunc = clamp(balanceFunc, 0, 1);

                float3 skyColor = lerp(midColor, 1.0 * topColor, balanceFunc);

                return skyColor;
            }


            fixed4 frag(v2f i) : SV_Target
            {
                float4 normWorldPos = normalize(i.worldPos);
                
                float altitude = normWorldPos.g * 0.5 + 0.5;

                float3 skyColor = GetSkyColor(_TimeOfDay, altitude);

                float4 col = float4(skyColor, 1.0);

                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return normWorldPos * 0.50 + 0.50;
            }
            ENDCG
        }
    }
}
