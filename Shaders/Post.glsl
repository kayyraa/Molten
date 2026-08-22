#pragma language glsl3

uniform vec2 Resolution;
uniform float DenoiseStrength;
uniform float FxaaQuality;
uniform float TemporalAlpha;   // higher = trust current frame more (motion)
uniform float FrameIndex;
uniform float RestirRadius;    // spatial reservoir radius in pixels
uniform float RestirSamples;   // number of spatial candidates
uniform Image HistoryTex;

vec3 luminanceWeights = vec3(0.299, 0.587, 0.114);

float luma(vec3 c) {
    return dot(c, luminanceWeights);
}

// Tiny hash for reservoir candidate selection
float Hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec2 Hash22(vec2 p) {
    float n = Hash21(p);
    return vec2(n, Hash21(p + n + 17.13));
}

// ---------------------------------------------------------------------------
// Spatial reservoir resampling (screen-space ReSTIR-inspired)
// Samples neighboring pixels as candidate "light paths", weights by luminance
// similarity (proxy for geometric/material consistency without a G-buffer).
// ---------------------------------------------------------------------------
vec3 SpatialReservoir(Image src, vec2 uv, vec2 texel, float radius, int samples) {
    vec3 center = Texel(src, uv).rgb;
    float cl = luma(center);

    // Reservoir state: selected sample, weight sum, M count
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

        // Similarity weight: reject large luminance discontinuities (edges)
        float range = exp(-12.0 * abs(sl - cl));
        float spatial = exp(-0.08 * rad * rad);
        float w = max(sl, 1e-4) * range * spatial;

        wSum += w;
        M += 1.0;
        // Reservoir update: probability w / wSum of replacing
        float p = w / max(wSum, 1e-4);
        if (Hash21(seed + float(i) * 3.7 + 0.5) < p) {
            selected = s;
        }
    }

    // Unbiased contribution estimate: selected * (wSum / M) / p_selected ≈ average
    // We blend toward a weighted mean for stability in an editor viewport
    vec3 meanish = mix(center, selected, 0.55);
    // Soft pull toward neighborhood mean via second pass weight
    return mix(center, meanish, clamp(DenoiseStrength * 0.85, 0.0, 0.9));
}

// Temporal reservoir: blend current reservoir result with history
vec3 TemporalReservoir(vec3 current, vec2 uv, float alpha) {
    vec4 hist = Texel(HistoryTex, uv);
    // hist.a encodes previous luma confidence; if zero, no history yet
    if (hist.a < 0.01) {
        return current;
    }
    vec3 h = hist.rgb;
    float cl = luma(current);
    float hl = luma(h);
    // Reject history on large lighting/content changes (disocclusion proxy)
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
            float range   = exp(-16.0 * abs(sl - cl));
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

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 texel = 1.0 / max(Resolution, vec2(1.0));
    vec2 uv = texture_coords;

    int samples = int(clamp(RestirSamples, 1.0, 16.0));
    float radius = max(RestirRadius, 1.0);

    // 1) Spatial reservoir resampling over noisy shaded neighbors
    vec3 restir = SpatialReservoir(tex, uv, texel, radius, samples);

    // 2) Temporal reservoir: reuse history when camera is stable
    float alpha = clamp(TemporalAlpha, 0.05, 0.95);
    vec3 temporal = TemporalReservoir(restir, uv, alpha);

    // 3) Edge-aware denoise + FXAA polish
    // Write temporal result through a lightweight bilateral-ish mix
    vec3 denoised = denoise(tex, uv, texel);
    vec3 mixed = mix(denoised, temporal, 0.65);

    vec3 aa = fxaa(tex, uv, texel, max(4.0, FxaaQuality));
    float edge = abs(luma(aa) - luma(mixed));
    vec3 finalRgb = mix(mixed, aa, clamp(edge * 3.5, 0.0, 0.25));

    return vec4(finalRgb, 1.0);
}