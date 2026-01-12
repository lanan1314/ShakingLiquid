Shader "Unlit/WaterBody"
{
    Properties
    {
        [Header(Dynamic)][Space(10)]
        _Scale ("Scale", vector) = (1,1,1,1)
        _Level ("Level", Range(0, 1)) = 0.5
        _MaxAngle ("Max Angle", Range(0, 90)) = 90
        [Toggle(WAVE)] _WAVE ("Wave", Float) = 0 
        _WaveFrequency ("Wave Frequency", float) = 10
        _WaveStrength ("Wave Strength", float) = 0.1
        _WaveSpeed ("Wave Speed", float) = 1

        [Header(Surface)][Space(10)]
        [Toggle(TWOCOLOR)] _TWOCOLOR ("Two Color", Float) = 0 
        _SurfaceColor ("Surface Color", Color) = (1,1,1,1)
        _SideColor ("Side Color", Color) = (1,1,1,1)
        [Toggle(RIM)] _RIM ("Rim", Float) = 0 
        _RimPower ("Rim Power", float) = 2
        _RimStrength ("Rim Strength", float) = 1
        [Toggle(HAT)] _HAT ("Hat", Float) = 0 
        _HatRange ("Hat Range", Range(0, 1)) = 0.05
        _HatSoft ("Hat Soft", Range(0, 1)) = 0.8
        [Toggle(BUBBLE)] _BUBBLE ("Bubble", Float) = 0 
        _BubbleNoise ("Bubble Noise", 2D) = "white"{}
        _BubbleColor ("Bubble Color", Color) = (1,1,1,1)
//        [Toggle(LEVEL)] _LEVEL ("Level", Float) = 0 
//        [Toggle(LEVEL_TEX)] _LEVEL_TEX ("Use Level Tex", Float) = 0 
//        _LevelTex ("Level Tex", 2D) = "white"{}
        [Toggle(CUBEMAP)] _CUBEMAP ("Cube Map", float) = 0
        _Environment("环境模拟", Cube) = "" {}
        _Opacity("环境强度", Range(0, 1)) = 0.5
        _EtaRatio("折射率", Range(0, 1)) = 0
        _FresnelBias("折射基础值", float) = .5
        _FresnelScale("折射倍率", float) = .5
        _FresnelWrap("折射范围", float) = .5 

        [Header(Adaptive)][Space(10)]
        _WorldHeightRange("World Height Range", vector) = (0, 1, 0, 0)
        _Wobble("Wobble", vector) = (0, 0, 0, 0)
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Geometry"
            "IgnoreProjector"="True"
            "DisableBatching"="True"
        }
        Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS   : NORMAL;
            float2 uv         : TEXCOORD0;
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float3 positionWS : TEXCOORD1;
            float3 normalWS   : TEXCOORD2;
            float3 viewDirWS  : TEXCOORD3;
            float2 uv         : TEXCOORD0;
            float  fogCoord   : TEXCOORD4;
            float3 localPos   : TEXCOORD5;
        };

        TEXTURE2D(_BubbleNoise);        SAMPLER(sampler_BubbleNoise);
        TEXTURE2D(_LevelTex);           SAMPLER(sampler_LevelTex);
        TEXTURECUBE(_Environment);      SAMPLER(sampler_Environment);

        CBUFFER_START(UnityPerMaterial)
            float4 _Scale;
            float4 _WorldHeightRange;
            float4 _Wobble;
            float4 _BubbleNoise_ST;
            float  _Level;
            float  _MaxAngle;
            float  _WaveFrequency;
            float  _WaveStrength;
            float  _WaveSpeed;
            float4 _SurfaceColor;
            float4 _SideColor;
            float  _RimPower;
            float  _RimStrength;
            float  _HatRange;
            float  _HatSoft;
            float4 _BubbleColor;
            float  _Opacity;
            float  _EtaRatio;
            float  _FresnelBias;
            float  _FresnelScale;
            float  _FresnelWrap;
            float  _LevelCount;
            float4 _LevelColors[32];
        CBUFFER_END

        float3 CalculateReflectDir(float3 V, float3 N)
        {
            return V - 2 * N * dot(V, N);
        }

        float3 CalculateRefractDir(float3 V, float3 N, float etaRatio)
        {
            float cosTheta  = dot(-V, N);
            float cosTheta2 = sqrt(saturate(1 - (etaRatio * etaRatio) * (1 - cosTheta * cosTheta)));
            return etaRatio * (V + N * cosTheta) - N * cosTheta2;
        }

        float CalculateFresnel(float3 V, float3 N)
        {
            return saturate(_FresnelBias + _FresnelScale * pow(saturate(1 - dot(V, N)), _FresnelWrap));
        }

        // 控制环境贴图与液体颜色的叠加
        float4 BlendOverlay(float4 Base, float4 Blend, float Opacity)
        {
            float4 result1 = 1.0 - 2.0 * (1.0 - Base) * (1.0 - Blend);
            float4 result2 = 2.0 * Base * Blend;
            float4 zeroOrOne = step(Base, 0.5);
            float4 Out = result2 * zeroOrOne + (1 - zeroOrOne) * result1;
            return lerp(Base, Out, Opacity);
        }

        // 将局部坐标绕任意轴旋转
        float3 RotateAboutAxis_Radians(float3 In, float3 Axis, float Rotation)
        {
            float s = sin(Rotation);
            float c = cos(Rotation);
            float one_minus_c = 1.0 - c;
            Axis = normalize(Axis);
            float3x3 rot_mat =
            {
                one_minus_c * Axis.x * Axis.x + c,                one_minus_c * Axis.x * Axis.y - Axis.z * s,      one_minus_c * Axis.z * Axis.x + Axis.y * s,
                one_minus_c * Axis.x * Axis.y + Axis.z * s,       one_minus_c * Axis.y * Axis.y + c,               one_minus_c * Axis.y * Axis.z - Axis.x * s,
                one_minus_c * Axis.z * Axis.x - Axis.y * s,       one_minus_c * Axis.y * Axis.z + Axis.x * s,      one_minus_c * Axis.z * Axis.z + c
            };
            return mul(rot_mat, In);
        }

        float3 RotateAboutAxis_Angle(float3 In, float3 Axis, float Angle)
        {
            float Rotation = radians(Angle);
            return RotateAboutAxis_Radians(In, Axis, Rotation);
        }

        // 计算带晃动的世界坐标，同时裁掉液面以上的像素
        float3 FluidWorldPos(float3 localPos, float3 worldPos)
        {
            // 世界空间液面高度
            float level = lerp(_WorldHeightRange.x, _WorldHeightRange.y, _Level);

            // 随移动晃动：按最大旋转角度限制，将局部坐标绕 x/z 轴旋转
            float3 xRotation = RotateAboutAxis_Angle(localPos, float3(1,0,0), _MaxAngle);
            float3 zRotation = RotateAboutAxis_Angle(xRotation, float3(0,0,1), _MaxAngle);

            // 倾倒强度
            float xWobble = _Wobble.x;
            float zWobble = _Wobble.z;
            
            // #if defined(WAVE)
            xWobble *= 1 + sin(localPos.x * _WaveFrequency + _Time.y * _WaveSpeed) * _WaveStrength; 
            zWobble *= 1 + sin(localPos.z * _WaveFrequency + _Time.y * _WaveSpeed) * _WaveStrength; 
            // #endif

            // 将偏移叠加到世界坐标，得到晃动后的顶点位置
            float3 worldPos2 = worldPos + xRotation * xWobble + zRotation * zWobble;

            // 最终液平面
            float fluid = level - worldPos2.y;
            clip(fluid);

            return worldPos2;
        }

        Varyings vert(Attributes IN)
        {
            Varyings OUT;
            VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
            VertexNormalInputs   nrmInputs = GetVertexNormalInputs(IN.normalOS);

            float3 scaledOS = IN.positionOS.xyz * _Scale.xyz;
            OUT.positionCS = posInputs.positionCS;
            OUT.positionWS = posInputs.positionWS;
            OUT.normalWS   = NormalizeNormalPerPixel(nrmInputs.normalWS);
            OUT.viewDirWS  = GetWorldSpaceViewDir(OUT.positionWS);
            OUT.uv         = TRANSFORM_TEX(IN.uv, _BubbleNoise);
            OUT.fogCoord   = ComputeFogFactor(posInputs.positionCS.z);
            OUT.localPos   = scaledOS;
            return OUT;
        }

        half4 frag(Varyings IN, bool frontFace : SV_IsFrontFace) : SV_Target
        {
            float facing = frontFace ? 1.0 : -1.0;
            float3 worldPos = FluidWorldPos(IN.localPos, IN.positionWS);

            float fragLevelInBottle = saturate((worldPos.y - _WorldHeightRange.x) / (_WorldHeightRange.y - _WorldHeightRange.x));
            float fragLevelInFluid  = saturate((IN.positionWS.y - _WorldHeightRange.x) / (_WorldHeightRange.y * _Level - _WorldHeightRange.x));

            float4 frontColor = 1;
            float4 backColor  = 1;

            #if defined(TWOCOLOR)
                frontColor = _SurfaceColor;
                backColor  = _SideColor;
            #endif

            // 边缘光
            #if defined(RIM)
                float rim = pow(abs(dot(IN.normalWS, normalize(IN.viewDirWS))), _RimPower);
                backColor = lerp(backColor * _RimStrength, backColor, rim);
            #endif

            #if defined(HAT)
                float hat = smoothstep(_Level - _HatRange, _Level - _HatRange * _HatSoft, fragLevelInBottle);
                backColor = lerp(backColor, frontColor, hat);
            #endif

            // 气泡
            #if defined(BUBBLE)
                float bubbleRange = smoothstep(_Level - _HatRange * _Wobble.w, _Level - _HatRange * _HatSoft * _Wobble.w, fragLevelInBottle);
                float2 bubbleUV = IN.uv * _BubbleNoise_ST.xy + float2(0, _BubbleNoise_ST.y * _Time.y);
                float bubble = SAMPLE_TEXTURE2D(_BubbleNoise, sampler_BubbleNoise, bubbleUV).r * fragLevelInFluid;
                bubble = smoothstep(_BubbleNoise_ST.z, _BubbleNoise_ST.w, bubble * _Wobble.w) * _Wobble.w;
                backColor = lerp(backColor, _BubbleColor, bubble);
            #endif

            #if defined(CUBEMAP)
                float3 V = normalize(IN.viewDirWS);
                float3 N = normalize(IN.normalWS) * facing;
                float3 reflectedDir = -CalculateReflectDir(V, N);
                float3 refractedDir = -CalculateRefractDir(V, N, _EtaRatio);
                float fresnel = CalculateFresnel(V, N);
                float4 reflectCol = SAMPLE_TEXTURECUBE(_Environment, sampler_Environment, reflectedDir);
                float4 refractCol = SAMPLE_TEXTURECUBE(_Environment, sampler_Environment, refractedDir);
                float4 environment = lerp(refractCol, reflectCol, fresnel);
                // float hatMask = defined(HAT) ? smoothstep(_Level - _HatRange, _Level - _HatRange * _HatSoft, fragLevelInBottle) : 0;
                backColor = BlendOverlay(backColor, environment, _Opacity * (1 - hat));
            #endif

            // #if defined(LEVEL)
            //     const int MAXLEVEL = 32;
            //     float perLevel = 1.0 / MAXLEVEL;
            //     float level = fragLevelInBottle * _LevelCount * perLevel;
            //     backColor = _LevelColors[0];
            //     [loop]
            //     for (int idx = 1; idx < _LevelCount; idx++)
            //     {
            //         float temp = step(perLevel, level - perLevel * (idx - 1));
            //         backColor = lerp(backColor, _LevelColors[idx], temp);
            //     }
            //     int currentLevel = clamp((int)floor(_Level * _LevelCount), 0, MAXLEVEL - 1);
            //     frontColor = _LevelColors[currentLevel] + _SurfaceColor;
            //
            //     #if defined(LEVEL_TEX)
            //         float perCount = 1.0 / _LevelCount;
            //         float uvY = saturate((fragLevelInBottle - currentLevel * perCount) / perCount);
            //         float2 levelUV = float2(IN.uv.x * _LevelCount, uvY);
            //         float4 levelTex = SAMPLE_TEXTURE2D(_LevelTex, sampler_LevelTex, levelUV);
            //         backColor.rgb = lerp(backColor.rgb, levelTex.rgb, levelTex.a);
            //     #endif
            // #endif

            float4 color = lerp(frontColor, backColor, facing > 0);
            color.rgb = MixFog(color.rgb, IN.fogCoord);
            return color;
        }
        ENDHLSL

        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma shader_feature_local _ TWOCOLOR
            #pragma shader_feature_local _ RIM
            #pragma shader_feature_local _ HAT
            #pragma shader_feature_local _ BUBBLE
            #pragma shader_feature_local _ LEVEL
            #pragma shader_feature_local _ LEVEL_TEX
            #pragma shader_feature_local _ CUBEMAP
            ENDHLSL
        }
    }
}