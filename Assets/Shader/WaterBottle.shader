Shader "Unlit/WaterBottle"
{
    Properties
    {
        [Header(Transparency)]
        _Alpha ("Base Opacity", Range(0, 0.5)) = 0.05 // 极低，几乎全透
        _FresnelPower ("Edge Opacity Power", Range(0.5, 10)) = 5.0

        [Header(Reflection)]
        _Smoothness ("Smoothness", Range(0.8, 1.0)) = 0.98
        _ReflectIntensity ("Environment Reflection", Range(0, 5)) = 2.0 // 增强环境反射
        
        [Header(Specular)]
        _SpecColor ("Highlight Color", Color) = (1, 1, 1, 1)
        _SpecPower ("Highlight Size", Range(10, 1000)) = 500.0
        _SpecIntensity ("Highlight Brightness", Range(1, 10)) = 3.0

        [Header(Details)]
        _Iridescence ("Rainbow Effect", Range(0, 1)) = 0.2 // 模拟晶体色散
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            // 开启 URP 的反射探针支持
            #pragma multi_compile _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile _ _REFLECTION_PROBE_BLENDING

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 viewDirWS : TEXCOORD2;
            };

            CBUFFER_START(UnityPerMaterial)
                float _Alpha;
                float _FresnelPower;
                float _Smoothness;
                float _ReflectIntensity;
                float4 _SpecColor;
                float _SpecPower;
                float _SpecIntensity;
                float _Iridescence;
            CBUFFER_END

            // 简单的彩虹色散函数
            float3 CalculateIridescence(float NdotV)
            {
                float factor = NdotV * 6.0 + _Time.y * 0.5;
                return float3(sin(factor), sin(factor + 2.09), sin(factor + 4.18)) * 0.5 + 0.5;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.viewDirWS = GetWorldSpaceNormalizeViewDir(output.positionWS);
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                // 1. 准备向量
                float3 N = normalize(input.normalWS);
                float3 V = normalize(input.viewDirWS);
                float3 L = normalize(_MainLightPosition.xyz);
                float3 H = normalize(L + V);
                float3 R = reflect(-V, N); // 反射向量

                float NdotV = saturate(dot(N, V));
                
                // 2. 计算环境反射 (Environment Reflection) - 核心！
                // 这里我们手动采样 Unity 的反射探针(Reflection Probe)或天空盒
                float3 reflection = 0;
                
                // 构建 URP 反射数据结构
                // 注意：为了性能和简化，这里假设 roughnes 很低
                float smoothness = _Smoothness;
                float perceptualRoughness = 1.0 - smoothness;
                float roughness = perceptualRoughness * perceptualRoughness;
                
                // 采样环境 cubemap
                float3 encodedIrradiance = SampleSH(N); // 漫反射环境光（虽然我们几乎不用，但作为底色）
                float3 environmentColor = GlossyEnvironmentReflection(R, perceptualRoughness, 1.0);
                
                reflection = environmentColor * _ReflectIntensity;

                // 3. 主光高光 (Direct Specular)
                float NdotH = saturate(dot(N, H));
                float specularTerm = pow(NdotH, _SpecPower);
                float3 specular = _SpecColor.rgb * specularTerm * _SpecIntensity;

                // 4. 菲涅尔混合 (Fresnel)
                // 边缘不透明度高，中心低
                float fresnel = pow(1.0 - NdotV, _FresnelPower);
                
                // 5. 色散细节 (Iridescence)
                // 在高光和反射中加入一点点彩虹色，模拟晶莹剔透的感觉
                float3 rainbow = CalculateIridescence(NdotV) * _Iridescence * fresnel;
                reflection += rainbow;

                // 6. 最终合成
                // 这种材质几乎没有漫反射，主要是 反射 + 高光
                float3 finalColor = reflection + specular;

                // 7. 透明度计算
                // 核心：_Alpha 是基础透明度(很低)，fresnel 增加边缘不透明度
                // 高光区域必须不透明，否则亮不起来
                float alpha = saturate(_Alpha + fresnel + specularTerm);

                return float4(finalColor, alpha);
            }
            ENDHLSL
        }
    }
}