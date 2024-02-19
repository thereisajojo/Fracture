Shader "Fracture/Sphere"
{
    Properties
    {
        [MainTexture] _BaseMap("Texture", 2D) = "white" {}
        [MainColor][HDR] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [HDR] _FractureColor("Fracture Color", Color) = (0.5, 0.5, 0.5, 1)
        _FractureDir("Dir", Vector) = (1,1,1,1)
        _Strength("Strength", Float) = 1
        //_DepthRange("Depth Range", Float) = 1
        _NoiseTexture("Noise", 2D) = "black"{}
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent" "RenderPipeline" = "UniversalRenderPipeline" "Queue" = "Transparent"
        }

        Pass
        {
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite On
            Cull Off

            HLSLPROGRAM
            #pragma multi_compile_instancing

            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
                float2 uv2 : TEXCOORD2;
                float3 normal : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float strength : TEXCOORD1;
                float4 screenPos : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
                float3 positionWS : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half4 _FractureColor;
            float _Cutoff;
            float4 _FractureDir;
            float _Strength;
            float _DepthRange;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);

            TEXTURE2D(_NoiseTexture);
            SAMPLER(sampler_NoiseTexture);

            Varyings vert(Attributes input)
            {
                Varyings output;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                // Baked Pivot
                float3 cellPos = float3(input.uv1.xy, input.uv2.x);
                cellPos = cellPos * 2 - 1;
                cellPos.z = -cellPos.z; // z轴烘焙反了
                float3 cellDirWS = TransformObjectToWorldDir(cellPos);

                float3 fractureDir = normalize(_FractureDir.xyz);
                float d = dot(fractureDir, cellDirWS); // -1 ~ 1
                float strength = smoothstep(_FractureDir.w, _FractureDir.w + _Strength, d);

                float3 offsetDir = (cellPos - input.positionOS.xyz) * strength;
                float3 positionOS = input.positionOS.xyz + offsetDir;

                output.positionWS = TransformObjectToWorld(positionOS.xyz);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.strength = strength;
                output.screenPos = ComputeScreenPos(output.positionCS);

                // 球形直接用顶点方向当法线（破碎后的模型法线可能有问题）
                output.normalWS = TransformObjectToWorldNormal(normalize(input.positionOS.xyz));
                
                return output;
            }

            #define _Radius 1.0 // 球体半径

            half4 frag(Varyings input, float face : VFACE) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float2 screenUV = input.screenPos.xy / input.screenPos.w;

                float3 normalWS = normalize(input.normalWS);
                // normalWS *= face > 0 ? 1 : -1;
                float3 viewDir = normalize(GetCameraPositionWS() - input.positionWS);
                float fresnel = pow(1 - saturate(dot(normalWS, viewDir)), 8) * 2;
                fresnel = face > 0 ? fresnel : 0;

                float sceneDepth = SampleSceneDepth(screenUV);
                sceneDepth = LinearEyeDepth(sceneDepth, _ZBufferParams);
                float selfDepth = input.screenPos.w;
                // 写入了深度，无法显示后方的相交效果，所以我们手动计算后方的位置
                float3 newPosWS = _WorldSpaceCameraPos - (_WorldSpaceCameraPos - input.positionWS) / selfDepth * sceneDepth;

                float3 objectPos = UNITY_MATRIX_M._m03_m13_m23;
                float objectScaleX = length(float3(UNITY_MATRIX_M[0].x, UNITY_MATRIX_M[1].x, UNITY_MATRIX_M[2].x));
                float intersection = saturate(1 - abs(distance(newPosWS, objectPos) - objectScaleX * _Radius));
                intersection = pow(intersection, 15);

                half3 emission = _BaseColor.rgb * (fresnel + intersection);

                float noise1 = SAMPLE_TEXTURE2D(_NoiseTexture, sampler_NoiseTexture, float2(screenUV.x + _Time.y * 0.01, screenUV.y)).r;
                float noise2 = SAMPLE_TEXTURE2D(_NoiseTexture, sampler_NoiseTexture, float2(screenUV.x - _Time.y * 0.01, screenUV.y + 0.3)).r;
                float noise = (noise1 + noise2) * 2 - 2;
                half3 screenCol = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, screenUV + noise * 0.01).rgb;

                half3 col = lerp(_BaseColor.rgb, _FractureColor.rgb, input.strength);
                screenCol = lerp(screenCol, col, 0.1);

                return half4(screenCol + emission , 1);
            }
            ENDHLSL
        }
    }
}