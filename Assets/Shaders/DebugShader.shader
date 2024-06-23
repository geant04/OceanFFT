Shader "Custom/DebugShader"
{
    Properties
    {
        // darker green colors
        _ScatterColor("Scatter Color", Color) = (0.81761, 0.9982171, 1.0,1)
        _BubbleColor("Bubble Color", Color) = (0.01370592, 0.1456759, 0.1792453, 1)
        _SunColor("Sun Color", Color) = (1.0, 1.0, 1.0, 1)

        // fun parameters for tweaking
        _Range("Range", Range(0,1)) = 0.642
        _Bias("Height Bias", Range(0,1)) = 0
        _k1("Height Scatter Strength", Range(0,1)) = 0.546
        _k2("Light Reflectance", Range(0, 1)) = 0.18
        _k3("Lambert bias", Range(0,1)) = 0.146
        _pf("Bubble density", Range(0,1)) = 0.566
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
        #include "Lighting.cginc"

        sampler2D _DisplacementTexture;
        float _N;

        float4 _ScatterColor, _BubbleColor, _SunColor;
        float _SunThreshold, _Range, _Bias;
        float _k1, _k2, _k3, _pf;

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
            i.viewDir = WorldSpaceViewDir(float4(localVertex, 1.0));

            return i;
        }

        float3 getNormal(float2 uv)
        {
            // https://web.archive.org/web/20101129095145/http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.161.8979&rep=rep1&type=pdf
            float texelSize = 1.0 / 256.0;
            float texelAspect = 256 * 8;

            // experiment with calculating the normal in the shader; might be super slow
            float4 h;
            h.x = texelAspect * tex2D(_DisplacementTexture, uv + texelSize * float2(0, -1)).r;
            h.y = texelAspect * tex2D(_DisplacementTexture, uv + texelSize * float2(-1, 0)).r;
            h.z = texelAspect * tex2D(_DisplacementTexture, uv + texelSize * float2(1, 0)).r;
            h.w = texelAspect * tex2D(_DisplacementTexture, uv + texelSize * float2(0, 1)).r;

            float3 n;
            n.z = h.w - h.x;
            n.x = h.y - h.z;
            n.y = 2;

            return normalize(n);
        }

        // from the beautiful Atlas presentation
        float3 L_Scatter(float3 wi, float3 wo, float3 wh, float h) {
            float H = max(0, h) * 2.0;
            float hTerm = _k1 * H * pow(max(dot(wo, -wi), 0.0), 4.0);
            float halfLamb = pow(0.5 - 0.5 * max(dot(wi, wh), 0.0), 1.0);
            float refl = _k2 * pow(max(dot(wo, wh), 0.0), 2.0);

            float lambert = _k3 * max(dot(wh, wi), 0.0);
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
            float2 uv = i.uv;

            // resolution = 256
            // ocean size = patch size? or something??
            float3 normal = getNormal(i.uv);

            // height sample
            float4 dy = tex2D(_DisplacementTexture, uv).r * 10;

            // actual stuff
            float3 wo = normalize(-i.viewDir);
            float3 wi = normalize(_WorldSpaceLightPos0);
            float3 wh = normalize(-wo + normal);

            float3 l_sctr = L_Scatter(wi, -wo, wh, 0.6 * dy + 0.01);

            float3 F = fresnelSchlicK(max(dot(wh, -wo), 0.0));
            float3 fresNor = normal * 0.3 + float3(0, 0.05, 0);
            float3 refl = normalize(reflect(-wo, fresNor * 1.2));
            float3 env_irradiance = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, refl);
            float3 lo_env = F * env_irradiance * 6.0 * (dy + 0.20);

            wh = normalize(-wo + wi);
            float3 spec = pow(abs(dot(normal, wh)), 128.0);
            float3 lo_sun = _LightColor0.xyz * spec * 1;

            float3 lo = lo_env + (1 - F) * l_sctr + lo_sun;
            
            return float4(lo, 1.0);
        }

        ENDCG
        }
    }
    FallBack "Diffuse"
}
