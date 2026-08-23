#pragma language glsl3

uniform vec2 Resolution;
uniform float DenoiseStrength;
uniform float FxaaQuality;
uniform float TemporalAlpha;
uniform float FrameIndex;
uniform float RestirRadius;
uniform float RestirSamples;
uniform Image HistoryTex;

uniform float BloomEnabled;
uniform float BloomIntensity;
uniform float BloomSize;
uniform float BloomThreshold;

uniform float CcEnabled;
uniform float CcBrightness;
uniform float CcContrast;
uniform float CcSaturation;
uniform vec3 CcTint;

uniform float DofEnabled;
uniform float DofFarIntensity;
uniform float DofNearIntensity;
uniform float DofFocusDistance;
uniform float DofInFocusRadius;

uniform float SunRaysEnabled;
uniform float SunRaysIntensity;
uniform float SunRaysSpread;
uniform vec2 SunScreenPos;
uniform float SunVisible;

uniform float BlurEnabled;
uniform float BlurSize;

vec3 luminanceWeights = vec3(0.299, 0.587, 0.114);

float luma(vec3 c) {
    return dot(c, luminanceWeights);
}

float Hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec2 Hash22(vec2 p) {
    float n = Hash21(p);
    return vec2(n, Hash21(p + n + 17.13));
}

vec3 SpatialReservoir(Image src, vec2 uv, vec2 texel, float radius, int samples) {
    vec3 center = Texel(src, uv).rgb;
    float cl = luma(center);
    vec3 selected = center;
    float wSum = max(cl, 1e-4);
    float M = 1.0;
    vec2 seed = uv * Resolution + vec2(FrameIndex * 19.7, FrameIndex * 7.3);
    for (int i = 0; i < 16; i++) {
        if (i >= samples) break;
        vec2 rnd = Hash22(seed + float(i) * 13.1);
        float ang = rnd.x * 6.2831853;
        float rad = sqrt(rnd.y) * radius;
        vec2 offset = vec2(cos(ang), sin(ang)) * rad * texel;
        vec2 suv = clamp(uv + offset, texel, vec2(1.0) - texel);
        vec3 s = Texel(src, suv).rgb;
        float sl = luma(s);
        float range = exp(-12.0 * abs(sl - cl));
        float spatial = exp(-0.08 * rad * rad);
        float w = max(sl, 1e-4) * range * spatial;
        wSum += w;
        M += 1.0;
        float p = w / max(wSum, 1e-4);
        if (Hash21(seed + float(i) * 3.7 + 0.5) < p) {
            selected = s;
        }
    }
    vec3 meanish = mix(center, selected, 0.55);
    return mix(center, meanish, clamp(DenoiseStrength * 0.85, 0.0, 0.9));
}

vec3 TemporalReservoir(vec3 current, vec2 uv, float alpha) {
    vec4 hist = Texel(HistoryTex, uv);
    if (hist.a < 0.01) {
        return current;
    }
    vec3 h = hist.rgb;
    float cl = luma(current);
    float hl = luma(h);
    float trust = exp(-6.0 * abs(cl - hl));
    float w = (1.0 - alpha) * trust;
    return mix(current, h, clamp(w, 0.0, 0.92));
}

vec3 denoise(Image src, vec2 uv, vec2 texel) {
    vec3 center = Texel(src, uv).rgb;
    float cl = luma(center);
    vec3 accum = center;
    float wsum = 1.0;
    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            if (x == 0 && y == 0) continue;
            vec2 o = vec2(float(x), float(y)) * texel;
            vec3 s = Texel(src, uv + o).rgb;
            float sl = luma(s);
            float dist2 = float(x * x + y * y);
            float spatial = exp(-0.32 * dist2);
            float range = exp(-16.0 * abs(sl - cl));
            float w = spatial * range;
            accum += s * w;
            wsum += w;
        }
    }
    return mix(center, accum / max(wsum, 1e-4), clamp(DenoiseStrength, 0.0, 1.0));
}

vec3 fxaa(Image src, vec2 uv, vec2 texel, float quality) {
    vec3 rgbM = Texel(src, uv).rgb;
    float lumaM = luma(rgbM);
    float lumaN = luma(Texel(src, uv + vec2(0.0, -texel.y)).rgb);
    float lumaS = luma(Texel(src, uv + vec2(0.0,  texel.y)).rgb);
    float lumaE = luma(Texel(src, uv + vec2( texel.x, 0.0)).rgb);
    float lumaW = luma(Texel(src, uv + vec2(-texel.x, 0.0)).rgb);
    float lumaMin = min(lumaM, min(min(lumaN, lumaS), min(lumaE, lumaW)));
    float lumaMax = max(lumaM, max(max(lumaN, lumaS), max(lumaE, lumaW)));
    float lumaRange = lumaMax - lumaMin;
    if (lumaRange < max(0.0312, lumaMax * 0.125)) {
        return rgbM;
    }
    float lumaNW = luma(Texel(src, uv + vec2(-texel.x, -texel.y)).rgb);
    float lumaNE = luma(Texel(src, uv + vec2( texel.x, -texel.y)).rgb);
    float lumaSW = luma(Texel(src, uv + vec2(-texel.x,  texel.y)).rgb);
    float lumaSE = luma(Texel(src, uv + vec2( texel.x,  texel.y)).rgb);
    float edgeHorz = abs(lumaN + lumaS - 2.0 * lumaM) * 2.0
                   + abs(lumaNE + lumaSE - 2.0 * lumaE)
                   + abs(lumaNW + lumaSW - 2.0 * lumaW);
    float edgeVert = abs(lumaE + lumaW - 2.0 * lumaM) * 2.0
                   + abs(lumaNE + lumaNW - 2.0 * lumaN)
                   + abs(lumaSE + lumaSW - 2.0 * lumaS);
    bool horzSpan = edgeHorz >= edgeVert;
    float lengthSign = horzSpan ? texel.y : texel.x;
    float luma1 = horzSpan ? lumaN : lumaW;
    float luma2 = horzSpan ? lumaS : lumaE;
    float gradient1 = abs(luma1 - lumaM);
    float gradient2 = abs(luma2 - lumaM);
    if (gradient1 >= gradient2) {
        lengthSign = -lengthSign;
    }
    float gradientScaled = 0.25 * max(gradient1, gradient2);
    vec2 offset = horzSpan ? vec2(0.0, lengthSign * 0.5) : vec2(lengthSign * 0.5, 0.0);
    vec2 pos = uv + offset * (horzSpan ? vec2(0.0, 1.0) : vec2(1.0, 0.0));
    float spanMax = max(1.0, quality);
    vec2 stepUV = horzSpan ? vec2(texel.x, 0.0) : vec2(0.0, texel.y);
    float lumaEnd1 = lumaM;
    float lumaEnd2 = lumaM;
    bool done1 = false;
    bool done2 = false;
    vec2 pos1 = pos;
    vec2 pos2 = pos;
    for (int i = 0; i < 12; i++) {
        float t = float(i) + 1.0;
        if (t > spanMax) break;
        if (!done1) {
            pos1 -= stepUV;
            lumaEnd1 = luma(Texel(src, pos1).rgb);
            done1 = abs(lumaEnd1 - lumaM) >= gradientScaled;
        }
        if (!done2) {
            pos2 += stepUV;
            lumaEnd2 = luma(Texel(src, pos2).rgb);
            done2 = abs(lumaEnd2 - lumaM) >= gradientScaled;
        }
        if (done1 && done2) break;
    }
    float dist1 = horzSpan ? (uv.x - pos1.x) : (uv.y - pos1.y);
    float dist2 = horzSpan ? (pos2.x - uv.x) : (pos2.y - uv.y);
    float dist = min(dist1, dist2);
    float spanLen = dist1 + dist2;
    float pixelOffset = (dist / max(spanLen, 1e-4)) - 0.5;
    float subpix = abs(pixelOffset) * 2.0;
    subpix = clamp(subpix * subpix * 0.75, 0.0, 1.0);
    vec2 finalUV = uv;
    if (horzSpan) {
        finalUV.y += pixelOffset * lengthSign * subpix;
    } else {
        finalUV.x += pixelOffset * lengthSign * subpix;
    }
    return Texel(src, finalUV).rgb;
}

vec3 ApplyBloom(Image src, vec2 uv, vec2 texel, vec3 color) {
    if (BloomEnabled < 0.5) return color;
    float thr = max(BloomThreshold, 0.01);
    float size = max(BloomSize, 1.0);
    vec3 bloom = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 9; i++) {
        float ang = float(i) * 0.785398;
        for (int r = 1; r <= 4; r++) {
            float rad = float(r) * size * 0.35;
            vec2 o = vec2(cos(ang), sin(ang)) * rad * texel;
            vec3 s = Texel(src, clamp(uv + o, texel, vec2(1.0) - texel)).rgb;
            float b = max(0.0, luma(s) - thr);
            float w = exp(-float(r) * 0.55);
            bloom += s * b * w;
            wsum += w;
        }
    }
    bloom /= max(wsum, 1e-4);
    return color + bloom * BloomIntensity * 2.5;
}

vec3 ApplyColorCorrection(vec3 color) {
    if (CcEnabled < 0.5) return color;
    color += CcBrightness;
    color = (color - 0.5) * (1.0 + CcContrast) + 0.5;
    float gray = luma(color);
    color = mix(vec3(gray), color, 1.0 + CcSaturation);
    color *= CcTint;
    return clamp(color, 0.0, 1.0);
}

vec3 ApplyDof(Image src, vec2 uv, vec2 texel, vec3 color) {
    if (DofEnabled < 0.5) return color;
    float depthProxy = 1.0 - luma(color);
    float focus = clamp(DofFocusDistance / 200.0, 0.0, 1.0);
    float radius = max(DofInFocusRadius / 100.0, 0.05);
    float coc = abs(depthProxy - focus) / radius;
    float nearBlur = clamp(coc * DofNearIntensity, 0.0, 1.0);
    float farBlur = clamp(coc * DofFarIntensity, 0.0, 1.0);
    float blurAmt = max(nearBlur, farBlur);
    if (blurAmt < 0.02) return color;
    vec3 accum = color;
    float wsum = 1.0;
    float maxR = mix(1.0, 6.0, blurAmt);
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398 + 0.3;
        vec2 o = vec2(cos(a), sin(a)) * maxR * texel;
        vec3 s = Texel(src, clamp(uv + o, texel, vec2(1.0) - texel)).rgb;
        float w = 1.0;
        accum += s * w;
        wsum += w;
    }
    return mix(color, accum / wsum, clamp(blurAmt, 0.0, 0.85));
}

uniform float CloudCover;
uniform float CloudDensity;

vec3 ApplySunRays(Image src, vec2 uv, vec2 texel, vec3 color) {
    if (SunRaysEnabled < 0.5 || SunVisible < 0.5) return color;
    vec2 sun = SunScreenPos;
    if (sun.x < -0.15 || sun.x > 1.15 || sun.y < -0.15 || sun.y > 1.15) return color;

    float cloudBlock = clamp(CloudCover * CloudDensity, 0.0, 1.0);
    float rayStrength = SunRaysIntensity * (1.0 - cloudBlock * 0.85);
    if (rayStrength < 0.01) return color;

    float distToSun = length(sun - uv);
    float spread = mix(0.35, 1.15, clamp(SunRaysSpread, 0.0, 2.0));
    if (distToSun > spread * 1.4) return color;

    vec2 dir = (sun - uv);
    float steps = 24.0;
    vec2 stepUv = dir / steps;
    float decay = 0.92;
    float illum = 1.0;
    float densAccum = 0.0;
    vec3 shaft = vec3(0.0);
    vec2 pos = uv;

    for (int i = 0; i < 24; i++) {
        pos += stepUv;
        vec2 suv = clamp(pos, texel * 2.0, vec2(1.0) - texel * 2.0);
        vec3 s = Texel(src, suv).rgb;
        float L = luma(s);
        float bright = smoothstep(0.82, 1.15, L);
        float skyish = smoothstep(0.55, 0.95, L) * step(0.5, s.b + 0.15);
        float contrib = max(bright, skyish * 0.35);
        contrib *= contrib;
        illum *= decay;
        densAccum += contrib * illum;
        shaft += vec3(1.15, 1.05, 0.85) * contrib * illum;
    }

    shaft /= steps;
    densAccum /= steps;
    float radial = 1.0 - smoothstep(0.0, spread, distToSun);
    radial = pow(max(radial, 0.0), 1.35);
    float amount = densAccum * radial * rayStrength * 2.2;
    amount = clamp(amount, 0.0, 0.65);
    return color + shaft * amount;
}

vec3 ApplyBlur(Image src, vec2 uv, vec2 texel, vec3 color) {
    if (BlurEnabled < 0.5) return color;
    float size = max(BlurSize, 1.0) * 0.35;
    vec3 accum = color;
    float wsum = 1.0;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398;
        for (int r = 1; r <= 3; r++) {
            float rad = float(r) * size;
            vec2 o = vec2(cos(a), sin(a)) * rad * texel;
            vec3 s = Texel(src, clamp(uv + o, texel, vec2(1.0) - texel)).rgb;
            float w = exp(-float(r) * 0.45);
            accum += s * w;
            wsum += w;
        }
    }
    return accum / max(wsum, 1e-4);
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 texel = 1.0 / max(Resolution, vec2(1.0));
    vec2 uv = texture_coords;

    int samples = int(clamp(RestirSamples, 1.0, 16.0));
    float radius = max(RestirRadius, 1.0);

    vec3 restir = SpatialReservoir(tex, uv, texel, radius, samples);
    float alpha = clamp(TemporalAlpha, 0.05, 0.95);
    vec3 temporal = TemporalReservoir(restir, uv, alpha);
    vec3 denoised = denoise(tex, uv, texel);
    vec3 mixed = mix(denoised, temporal, 0.65);
    vec3 aa = fxaa(tex, uv, texel, max(4.0, FxaaQuality));
    float edge = abs(luma(aa) - luma(mixed));
    vec3 finalRgb = mix(mixed, aa, clamp(edge * 3.5, 0.0, 0.25));

    finalRgb = ApplyBlur(tex, uv, texel, finalRgb);
    finalRgb = ApplyBloom(tex, uv, texel, finalRgb);
    finalRgb = ApplyDof(tex, uv, texel, finalRgb);
    finalRgb = ApplySunRays(tex, uv, texel, finalRgb);
    finalRgb = ApplyColorCorrection(finalRgb);

    return vec4(clamp(finalRgb, 0.0, 1.0), 1.0);
}