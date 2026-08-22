#pragma language glsl3

// ---------------------------------------------------------------------------
// Rasterized path — same box scene data, single-hit hard lighting.
// Much cheaper than the full ray-traced Pixel.glsl (no GI / soft shadows /
// multi-bounce / glass paths). Hot-swapped via Lighting.Rendering.
// ---------------------------------------------------------------------------

struct Box {
    vec3 Position;
    vec3 Size;
    vec3 Orientation;
    vec3 Color;
    float HasDecal;
    vec2 UvStuds;
    vec2 UvOffset;
    float ColorTexIndex;
    float NormalTexIndex;
    float DecalTexIndex;
    vec3 DecalColor;
    float DecalAlpha;
    float Roughness;
    float Reflectivity;
    float Refractivity;
    float Transparency;
    float ShapeType;
    float IsHighlighted;
    float AlwaysOnTop;
    float CastShadows;
    float TriStart;
    float TriCount;
};

vec3 RotXYZ(vec3 v, vec3 e) {
    float cx = cos(e.x), sx = sin(e.x);
    float cy = cos(e.y), sy = sin(e.y);
    float cz = cos(e.z), sz = sin(e.z);
    float y1 = v.y * cx - v.z * sx;
    float z1 = v.y * sx + v.z * cx;
    float x1 = v.x;
    float x2 = x1 * cy + z1 * sy;
    float z2 = -x1 * sy + z1 * cy;
    float y2 = y1;
    float x3 = x2 * cz - y2 * sz;
    float y3 = x2 * sz + y2 * cz;
    return vec3(x3, y3, z2);
}

vec3 RotXYZInv(vec3 v, vec3 e) {
    float cx = cos(e.x), sx = sin(e.x);
    float cy = cos(e.y), sy = sin(e.y);
    float cz = cos(e.z), sz = sin(e.z);
    float x1 = v.x * cz + v.y * sz;
    float y1 = -v.x * sz + v.y * cz;
    float z1 = v.z;
    float x2 = x1 * cy - z1 * sy;
    float z2 = x1 * sy + z1 * cy;
    float y2 = y1;
    float y3 = y2 * cx + z2 * sx;
    float z3 = -y2 * sx + z2 * cx;
    return vec3(x2, y3, z3);
}

const int TRI_POOL_MAX = 96;
uniform vec4 TriPool[96];
uniform int TriPoolCount;

struct PointLightData {
    vec3 Position;
    vec3 Color;
    float Brightness;
    float Range;
    float Shadows;
};

uniform Box Boxes[24];
uniform int BoxCount;
const int ADORN_MAX = 8;
uniform Box AdornBoxes[8];
uniform int AdornCount;
uniform PointLightData Lights[8];
uniform int LightCount;

uniform vec2 Resolution;
uniform vec3 CameraPos;
uniform vec3 CameraForward;
uniform vec3 CameraRight;
uniform vec3 CameraUp;
uniform float Fov;
uniform float ClockTime;
uniform float GlobalShadows;
uniform float Time;

uniform float HighlightEnabled;
uniform vec3  HighlightFillColor;
uniform vec3  HighlightOutlineColor;
uniform float HighlightFillAlpha;
uniform float HighlightOutlineAlpha;

uniform sampler2D GlobalTextures[16];

vec4 SampleTexture(float Index, vec2 Uv) {
    int Idx = int(Index + 0.5);
    switch(Idx) {
        case 0: return Texel(GlobalTextures[0], Uv);
        case 1: return Texel(GlobalTextures[1], Uv);
        case 2: return Texel(GlobalTextures[2], Uv);
        case 3: return Texel(GlobalTextures[3], Uv);
        case 4: return Texel(GlobalTextures[4], Uv);
        case 5: return Texel(GlobalTextures[5], Uv);
        case 6: return Texel(GlobalTextures[6], Uv);
        case 7: return Texel(GlobalTextures[7], Uv);
        case 8: return Texel(GlobalTextures[8], Uv);
        case 9: return Texel(GlobalTextures[9], Uv);
        case 10: return Texel(GlobalTextures[10], Uv);
        case 11: return Texel(GlobalTextures[11], Uv);
        case 12: return Texel(GlobalTextures[12], Uv);
        case 13: return Texel(GlobalTextures[13], Uv);
        case 14: return Texel(GlobalTextures[14], Uv);
        case 15: return Texel(GlobalTextures[15], Uv);
    }
    return Texel(GlobalTextures[0], Uv);
}

vec2 GetBoxUv(vec3 HitPos, vec3 BoxPos, vec3 BoxSize, vec3 Normal) {
    vec3 LocalPos = (HitPos - BoxPos) / max(BoxSize, vec3(1e-5));
    vec2 Uv = vec2(0.0);
    if (abs(Normal.x) > 0.5) {
        Uv = Normal.x > 0.0 ? LocalPos.zy : -LocalPos.zy;
    } else if (abs(Normal.y) > 0.5) {
        Uv = Normal.y > 0.0 ? LocalPos.xz : -LocalPos.xz;
    } else {
        Uv = Normal.z > 0.0 ? -LocalPos.xy : LocalPos.xy;
    }
    return Uv + 0.5;
}

float IntersectBox(vec3 Ro, vec3 Rd, vec3 BoxPos, vec3 BoxHalf, out vec3 Normal) {
    vec3 InvRd = 1.0 / Rd;
    vec3 T0 = (BoxPos - BoxHalf - Ro) * InvRd;
    vec3 T1 = (BoxPos + BoxHalf - Ro) * InvRd;
    vec3 TMin3 = min(T0, T1);
    vec3 TMax3 = max(T0, T1);
    float TNear = max(max(TMin3.x, TMin3.y), TMin3.z);
    float TFar  = min(min(TMax3.x, TMax3.y), TMax3.z);
    if (TNear > TFar || TFar < 0.0) {
        Normal = vec3(0.0);
        return -1.0;
    }
    float T = (TNear > 0.0) ? TNear : TFar;
    const float Eps = 1e-4;
    vec3 N = vec3(0.0);
    if (TNear > 0.0) {
        if (abs(TNear - TMin3.x) < Eps * max(1.0, abs(TNear)))
            N = vec3(-sign(Rd.x), 0.0, 0.0);
        else if (abs(TNear - TMin3.y) < Eps * max(1.0, abs(TNear)))
            N = vec3(0.0, -sign(Rd.y), 0.0);
        else
            N = vec3(0.0, 0.0, -sign(Rd.z));
    } else {
        if (abs(TFar - TMax3.x) < Eps * max(1.0, abs(TFar)))
            N = vec3(sign(Rd.x), 0.0, 0.0);
        else if (abs(TFar - TMax3.y) < Eps * max(1.0, abs(TFar)))
            N = vec3(0.0, sign(Rd.y), 0.0);
        else
            N = vec3(0.0, 0.0, sign(Rd.z));
    }
    if (dot(N, N) < 0.5) {
        vec3 Hit = Ro + Rd * T;
        vec3 Local = (Hit - BoxPos) / max(BoxHalf, vec3(1e-5));
        vec3 A = abs(Local);
        if (A.x > A.y && A.x > A.z) N = vec3(sign(Local.x), 0.0, 0.0);
        else if (A.y > A.z) N = vec3(0.0, sign(Local.y), 0.0);
        else N = vec3(0.0, 0.0, sign(Local.z));
    }
    Normal = N;
    return T;
}

float IntersectSphere(vec3 Ro, vec3 Rd, vec3 Center, vec3 Size, out vec3 Normal) {
    float R = min(Size.x, min(Size.y, Size.z)) * 0.5;
    vec3 O = Ro - Center;
    float B = dot(O, Rd);
    float C = dot(O, O) - R * R;
    float Disc = B * B - C;
    if (Disc < 0.0) return -1.0;
    float S = sqrt(Disc);
    float T = -B - S;
    if (T < 0.001) T = -B + S;
    if (T < 0.001) return -1.0;
    Normal = normalize((Ro + Rd * T) - Center);
    return T;
}

float IntersectCylinder(vec3 Ro, vec3 Rd, vec3 Center, vec3 Size, out vec3 Normal) {
    float R = min(Size.x, Size.z) * 0.5;
    float Hy = Size.y * 0.5;
    vec3 O = Ro - Center;
    float A = Rd.x * Rd.x + Rd.z * Rd.z;
    float B = 2.0 * (O.x * Rd.x + O.z * Rd.z);
    float C = O.x * O.x + O.z * O.z - R * R;
    float Best = 1e9;
    vec3 BestN = vec3(0.0);
    bool Hit = false;
    if (A > 1e-8) {
        float Disc = B * B - 4.0 * A * C;
        if (Disc >= 0.0) {
            float S = sqrt(Disc);
            float T0 = (-B - S) / (2.0 * A);
            float T1 = (-B + S) / (2.0 * A);
            for (int i = 0; i < 2; i++) {
                float T = (i == 0) ? T0 : T1;
                if (T > 0.001) {
                    vec3 P = O + Rd * T;
                    if (abs(P.y) <= Hy && T < Best) {
                        Best = T;
                        BestN = normalize(vec3(P.x, 0.0, P.z));
                        Hit = true;
                    }
                }
            }
        }
    }
    if (abs(Rd.y) > 1e-6) {
        for (int s = 0; s < 2; s++) {
            float yFace = (s == 0) ? Hy : -Hy;
            float T = (yFace - O.y) / Rd.y;
            if (T > 0.001) {
                vec3 P = O + Rd * T;
                if (P.x * P.x + P.z * P.z <= R * R && T < Best) {
                    Best = T;
                    BestN = vec3(0.0, sign(yFace), 0.0);
                    Hit = true;
                }
            }
        }
    }
    if (!Hit) return -1.0;
    if (dot(BestN, Rd) > 0.0) BestN = -BestN;
    Normal = BestN;
    return Best;
}

float IntersectWedge(vec3 Ro, vec3 Rd, vec3 Center, vec3 Size, out vec3 Normal) {
    vec3 HalfSize = Size * 0.5;
    float T = IntersectBox(Ro, Rd, Center, HalfSize, Normal);
    if (T < 0.0) return -1.0;
    vec3 Hit = Ro + Rd * T;
    vec3 Local = (Hit - Center) / HalfSize;
    if (Local.x + Local.y > 0.02) {
        vec3 InvH = 1.0 / HalfSize;
        float Denom = Rd.x * InvH.x + Rd.y * InvH.y;
        if (abs(Denom) < 1e-8) return -1.0;
        float S = -(Local.x + Local.y) / Denom;
        float T2 = T + S;
        if (T2 < 0.0) return -1.0;
        Hit = Ro + Rd * T2;
        Local = (Hit - Center) / HalfSize;
        if (abs(Local.x) > 1.02 || abs(Local.y) > 1.02 || abs(Local.z) > 1.02) return -1.0;
        Normal = normalize(vec3(InvH.x, InvH.y, 0.0));
        if (dot(Normal, Rd) > 0.0) Normal = -Normal;
        return T2;
    }
    return T;
}

float IntersectCornerWedge(vec3 Ro, vec3 Rd, vec3 Center, vec3 Size, out vec3 Normal) {
    vec3 Half = Size * 0.5;
    float tEnter = 0.0;
    float tExit = 1e9;
    vec3 nEnter = vec3(0.0);
    vec3 Peak = Center + vec3(-Half.x, Half.y, Half.z);
    vec3 BXR = Center + vec3( Half.x, -Half.y,  Half.z);
    vec3 BXN = Center + vec3( Half.x, -Half.y, -Half.z);
    vec3 BNN = Center + vec3(-Half.x, -Half.y, -Half.z);
    vec3 nA = normalize(cross(BXR - Peak, BXN - Peak));
    if (dot(nA, BNN - Peak) > 0.0) nA = -nA;
    vec3 nB = normalize(cross(BNN - Peak, BXN - Peak));
    if (dot(nB, BXR - Peak) > 0.0) nB = -nB;

    vec3 boxN[6];
    float boxD[6];
    boxN[0] = vec3( 1.0, 0.0, 0.0); boxD[0] = Center.x + Half.x;
    boxN[1] = vec3(-1.0, 0.0, 0.0); boxD[1] = -(Center.x - Half.x);
    boxN[2] = vec3( 0.0, 1.0, 0.0); boxD[2] = Center.y + Half.y;
    boxN[3] = vec3( 0.0,-1.0, 0.0); boxD[3] = -(Center.y - Half.y);
    boxN[4] = vec3( 0.0, 0.0, 1.0); boxD[4] = Center.z + Half.z;
    boxN[5] = vec3( 0.0, 0.0,-1.0); boxD[5] = -(Center.z - Half.z);

    for (int i = 0; i < 6; i++) {
        vec3 n = boxN[i];
        float d = boxD[i];
        float denom = dot(n, Rd);
        float numer = d - dot(n, Ro);
        if (abs(denom) < 1e-8) {
            if (numer < -1e-5) return -1.0;
            continue;
        }
        float t = numer / denom;
        if (denom < 0.0) {
            if (t > tEnter) { tEnter = t; nEnter = -n; }
        } else {
            if (t < tExit) tExit = t;
        }
        if (tEnter > tExit) return -1.0;
    }
    for (int p = 0; p < 2; p++) {
        vec3 n = (p == 0) ? nA : nB;
        float d = dot(n, Peak);
        float denom = dot(n, Rd);
        float numer = d - dot(n, Ro);
        if (abs(denom) < 1e-8) {
            if (numer < -1e-5) return -1.0;
        } else {
            float t = numer / denom;
            if (denom < 0.0) {
                if (t > tEnter) { tEnter = t; nEnter = -n; }
            } else {
                if (t < tExit) tExit = t;
            }
            if (tEnter > tExit) return -1.0;
        }
    }
    if (tExit < 0.001) return -1.0;
    float T = (tEnter > 0.001) ? tEnter : tExit;
    if (T < 0.001) return -1.0;
    Normal = nEnter;
    if (length(Normal) < 0.1) IntersectBox(Ro, Rd, Center, Half, Normal);
    if (dot(Normal, Rd) > 0.0) Normal = -Normal;
    return T;
}

float IntersectCone(vec3 Ro, vec3 Rd, vec3 Center, vec3 Size, out vec3 Normal) {
    // Approximate cone as sphere for raster path (cheap)
    return IntersectSphere(Ro, Rd, Center, Size, Normal);
}

float IntersectShape(int I, vec3 Ro, vec3 Rd, out vec3 Normal) {
    int Shape = int(Boxes[I].ShapeType + 0.5);
    vec3 Pos  = Boxes[I].Position;
    vec3 Size = Boxes[I].Size;
    vec3 Ori  = Boxes[I].Orientation;
    float oa = abs(Ori.x) + abs(Ori.y) + abs(Ori.z);
    vec3 RoL = Ro;
    vec3 RdL = Rd;
    if (oa > 1e-5) {
        vec3 off = RotXYZInv(Ro - Pos, Ori);
        RoL = Pos + off;
        RdL = RotXYZInv(Rd, Ori);
    }
    float T;
    if (Shape == 1) T = IntersectSphere(RoL, RdL, Pos, Size, Normal);
    else if (Shape == 2) T = IntersectCylinder(RoL, RdL, Pos, Size, Normal);
    else if (Shape == 3) T = IntersectWedge(RoL, RdL, Pos, Size, Normal);
    else if (Shape == 4) T = IntersectCone(RoL, RdL, Pos, Size, Normal);
    else if (Shape == 5) T = IntersectCornerWedge(RoL, RdL, Pos, Size, Normal);
    else T = IntersectBox(RoL, RdL, Pos, Size * 0.5, Normal);
    if (T > 0.0 && oa > 1e-5) Normal = normalize(RotXYZ(Normal, Ori));
    return T;
}

int TraceScene(vec3 Ro, vec3 Rd, int SkipIndex, out float OutT, out vec3 OutNormal) {
    float Best = 1e9;
    int HitI = -1;
    vec3 HitN = vec3(0.0);
    for (int I = 0; I < BoxCount; I++) {
        if (I == SkipIndex) continue;
        vec3 N;
        float T = IntersectShape(I, Ro, Rd, N);
        if (T > 0.001 && T < Best) {
            Best = T;
            HitI = I;
            HitN = N;
        }
    }
    OutT = Best;
    OutNormal = HitN;
    return HitI;
}

float HardShadow(vec3 HitPos, vec3 N, vec3 SunDir, int SkipIndex) {
    if (GlobalShadows < 0.5) return 1.0;
    if (SunDir.y <= 0.0) return 0.25;
    vec3 Origin = HitPos + normalize(N) * 0.08 + SunDir * 0.05;
    for (int I = 0; I < BoxCount; I++) {
        if (I == SkipIndex) continue;
        if (Boxes[I].Transparency > 0.85) continue;
        vec3 Sn;
        float St = IntersectShape(I, Origin, SunDir, Sn);
        if (St > 0.02 && St < 1000.0) return 0.12;
    }
    return 1.0;
}

vec3 GetAtmosphere(vec3 Rd, vec3 SunDir) {
    vec3 DaySky   = mix(vec3(0.40, 0.60, 0.90), vec3(0.12, 0.22, 0.50), max(0.0, Rd.y));
    vec3 NightSky = mix(vec3(0.04, 0.05, 0.09), vec3(0.005, 0.008, 0.02), max(0.0, Rd.y));
    float SunFactor = clamp(SunDir.y, -0.25, 0.25) / 0.5 + 0.5;
    return mix(NightSky, DaySky, SunFactor);
}

vec3 GetSky(vec3 Rd, vec3 SunDir, vec3 MoonDir) {
    vec3 Sky = GetAtmosphere(Rd, SunDir);
    vec3 HorizonGlow = vec3(1.0, 0.55, 0.25);

    if (SunDir.y > -0.25 && SunDir.y < 0.25) {
        float H = max(0.0, 1.0 - abs(Rd.y) * 3.5);
        float SunDist = max(0.0, dot(Rd, normalize(vec3(SunDir.x, 0.0, SunDir.z))));
        Sky += HorizonGlow * H * pow(SunDist, 5.0) * (1.0 - abs(SunDir.y) * 4.0) * 1.8;
    }

    float SunDot = dot(Rd, SunDir);
    vec3 SunColor = vec3(1.6, 1.4, 1.1);
    float SunCore  = pow(max(0.0, SunDot), 8000.0);
    float SunBloom = pow(max(0.0, SunDot), 350.0) * 3.5;
    Sky += SunColor * SunCore * 18.0;
    Sky += vec3(1.3, 1.0, 0.6) * SunBloom * smoothstep(-0.2, 0.35, SunDir.y);

    float MoonDot = dot(Rd, MoonDir);
    vec3 MoonColor = vec3(0.9, 0.95, 1.25);
    float MoonCore  = pow(max(0.0, MoonDot), 12000.0);
    float MoonBloom = pow(max(0.0, MoonDot), 600.0) * 2.2;
    Sky += MoonColor * MoonCore * 14.0;
    Sky += MoonColor * MoonBloom * smoothstep(-0.2, 0.3, MoonDir.y);

    float SunFactor = clamp(SunDir.y, -0.25, 0.25) / 0.5 + 0.5;
    if (SunFactor < 0.65 && Rd.y > 0.04) {
        vec3 P = floor(Rd * 520.0);
        float StarVal = fract(sin(dot(P, vec3(127.1, 311.7, 74.7))) * 43758.5453);
        if (StarVal > 0.995) {
            float Intensity = pow((StarVal - 0.995) / 0.005, 2.0);
            Sky += vec3(1.5, 1.6, 1.9) * Intensity * (1.0 - SunFactor) * smoothstep(0.04, 0.22, Rd.y) * 22.0;
        }
    }
    return Sky;
}

float Hash13(vec3 P) {
    P = fract(P * 0.1031);
    P += dot(P, P.yzx + 33.33);
    return fract((P.x + P.y) * P.z);
}

// Cheap hemisphere AO (4 rays) — screenspace-ish via short world rays
float FastSSAO(vec3 HitPos, vec3 N, int SkipIndex) {
    float ao = 0.0;
    float radius = 1.8;
    // Fixed tangent basis
    vec3 T = normalize(abs(N.y) < 0.9 ? cross(N, vec3(0.0, 1.0, 0.0)) : cross(N, vec3(1.0, 0.0, 0.0)));
    vec3 B = cross(N, T);
    for (int i = 0; i < 4; i++) {
        float a = float(i) * 1.5707963 + 0.4;
        float h = 0.35 + 0.2 * float(i % 2);
        vec3 dir = normalize(N * h + T * cos(a) + B * sin(a));
        vec3 origin = HitPos + N * 0.06;
        float t; vec3 nn;
        int hi = TraceScene(origin, dir, SkipIndex, t, nn);
        if (hi >= 0 && t > 0.02 && t < radius) {
            ao += 1.0 - (t / radius);
        }
    }
    return clamp(1.0 - ao * 0.55, 0.25, 1.0);
}

// Roughness-aware reflection: 1 sharp ray + optional 2 blurred samples
vec3 FastReflection(vec3 HitPos, vec3 N, vec3 ViewDir, int SkipIndex,
                    float Roughness, float Reflectivity, vec3 SunDir, vec3 MoonDir) {
    vec3 R = reflect(-ViewDir, N);
    float Rr = clamp(Roughness, 0.0, 1.0);

    // Cone axis sample
    vec3 origin = HitPos + N * 0.08;
    float t; vec3 hn;
    int hi = TraceScene(origin, R, SkipIndex, t, hn);
    vec3 col;
    if (hi >= 0) {
        vec3 hp = origin + R * t;
        float ndl = max(0.0, dot(hn, SunDir));
        float sh = HardShadow(hp, hn, SunDir, hi);
        col = Boxes[hi].Color * (0.25 + 0.9 * ndl * sh);
        // tint by hit reflectivity slightly
        col = mix(col, GetSky(R, SunDir, MoonDir), clamp(t * 0.008, 0.0, 0.6));
    } else {
        col = GetSky(R, SunDir, MoonDir);
    }

    // Blur with 2 offset rays when rough
    if (Rr > 0.12) {
        vec3 T = normalize(abs(N.y) < 0.9 ? cross(R, vec3(0.0, 1.0, 0.0)) : cross(R, vec3(1.0, 0.0, 0.0)));
        vec3 B = cross(R, T);
        float spread = Rr * 0.35;
        for (int i = 0; i < 2; i++) {
            float a = float(i) * 2.399963 + 0.7;
            vec3 dir = normalize(R + (T * cos(a) + B * sin(a)) * spread);
            float t2; vec3 hn2;
            int hi2 = TraceScene(origin, dir, SkipIndex, t2, hn2);
            vec3 c2;
            if (hi2 >= 0) {
                float ndl = max(0.0, dot(hn2, SunDir));
                c2 = Boxes[hi2].Color * (0.3 + 0.7 * ndl);
            } else {
                c2 = GetSky(dir, SunDir, MoonDir);
            }
            col += c2;
        }
        col *= (1.0 / 3.0);
    }

    // Environment fill for very rough surfaces
    if (Rr > 0.55) {
        vec3 env = GetSky(normalize(N + vec3(0.0, 0.4, 0.0)), SunDir, MoonDir);
        col = mix(col, env, (Rr - 0.55) / 0.45 * 0.5);
    }
    return col;
}


vec4 effect(vec4 Color, Image Tex, vec2 TextureCoords, vec2 ScreenCoords) {
    vec2 Uv = (ScreenCoords - 0.5 * Resolution) / Resolution.y;
    float TanFov = tan(Fov * 0.5);
    vec3 RayDir = normalize(CameraForward + CameraRight * Uv.x * TanFov - CameraUp * Uv.y * TanFov);

    float MinT;
    vec3 HitNormal;
    int HitIndex = TraceScene(CameraPos, RayDir, -1, MinT, HitNormal);

    float DayAngle = (ClockTime - 6.0) / 24.0 * 6.2831853;
    vec3 SunDir = normalize(vec3(cos(DayAngle), sin(DayAngle), 0.28));
    vec3 MoonDir = normalize(vec3(-SunDir.x, -SunDir.y * 0.65 + 0.15, -SunDir.z));

    vec3 FinalColor;
    if (HitIndex != -1) {
        vec3 HitPos = CameraPos + RayDir * MinT;
        vec3 BaseColor = Boxes[HitIndex].Color;
        float Transparency = Boxes[HitIndex].Transparency;

        // Color map
        vec2 PartUv = GetBoxUv(HitPos, Boxes[HitIndex].Position, Boxes[HitIndex].Size, HitNormal);
        vec4 TexColor = SampleTexture(Boxes[HitIndex].ColorTexIndex, PartUv);
        BaseColor *= TexColor.rgb;

        // Decal / Texture on top face (same convention as Pixel.glsl)
        if (Boxes[HitIndex].HasDecal > 0.5 && HitNormal.y > 0.5) {
            vec2 DecalUv = HitPos.xz / max(Boxes[HitIndex].UvStuds, vec2(0.001))
                        + Boxes[HitIndex].UvOffset;
            vec4 DecalSample = SampleTexture(Boxes[HitIndex].DecalTexIndex, fract(DecalUv));
            vec3 Tinted = DecalSample.rgb * Boxes[HitIndex].DecalColor;
            float DA = DecalSample.a * Boxes[HitIndex].DecalAlpha;
            BaseColor = mix(BaseColor, Tinted, DA);
        }

        float Roughness = clamp(Boxes[HitIndex].Roughness, 0.0, 1.0);
        float Reflectivity = clamp(Boxes[HitIndex].Reflectivity, 0.0, 1.0);

        float wrap = max(0.0, (dot(HitNormal, SunDir) + 0.2) / 1.2);
        wrap = wrap * wrap;

        float Shadow = HardShadow(HitPos, HitNormal, SunDir, HitIndex);
        float AO = FastSSAO(HitPos, HitNormal, HitIndex);

        float Hemi = 0.5 + 0.5 * HitNormal.y;
        vec3 Ambient = mix(vec3(0.12, 0.13, 0.16), vec3(0.30, 0.34, 0.40), Hemi) * AO;
        vec3 SunLight = vec3(1.40, 1.28, 1.12) * wrap * Shadow * 2.4;

        vec3 ViewDir = normalize(CameraPos - HitPos);
        vec3 H = normalize(SunDir + ViewDir);
        float specPow = mix(64.0, 6.0, Roughness);
        float NdotH = max(0.0, dot(HitNormal, H));
        float sunSpec = pow(NdotH, specPow) * Shadow * mix(0.04, 0.9, Reflectivity) * (1.0 - Roughness * 0.5);

        float body = (1.0 - Reflectivity * mix(0.9, 0.55, Roughness)) * (1.0 - Transparency * 0.5);
        vec3 Lit = BaseColor * (SunLight + Ambient * 0.95) * body + vec3(sunSpec);

        for (int Li = 0; Li < 8; Li++) {
            if (Li >= LightCount) break;
            vec3 ToL = Lights[Li].Position - HitPos;
            float Dist = length(ToL);
            float Range = max(Lights[Li].Range, 0.01);
            if (Dist >= Range) continue;
            vec3 L = ToL / Dist;
            float atten = 1.0 - Dist / Range;
            atten *= atten;
            float ndl = max(0.0, dot(HitNormal, L));
            Lit += BaseColor * Lights[Li].Color * Lights[Li].Brightness * ndl * atten * 0.7 * body;
        }

        // Fast reflectivity + roughness reflections
        if (Reflectivity > 0.01) {
            vec3 Rcol = FastReflection(HitPos, HitNormal, ViewDir, HitIndex,
                                       Roughness, Reflectivity, SunDir, MoonDir);
            float CosTheta = max(0.0, dot(HitNormal, ViewDir));
            float F0 = mix(0.04, 0.92, Reflectivity);
            float Fresnel = F0 + (1.0 - F0) * pow(1.0 - CosTheta, 5.0);
            float Amt = Reflectivity * mix(Fresnel, 1.0, Reflectivity * 0.5);
            Amt *= (1.0 - Roughness * 0.35);
            Amt = clamp(Amt, 0.0, 1.0);
            vec3 Tint = mix(vec3(1.0), BaseColor, Reflectivity * 0.35);
            Lit += Rcol * Tint * Amt * AO;
        }

        if (Transparency > 0.05) {
            float Tt; vec3 Tn;
            int Ti = TraceScene(HitPos + RayDir * 0.08, RayDir, HitIndex, Tt, Tn);
            vec3 Behind = (Ti >= 0)
                ? Boxes[Ti].Color * (0.45 + 0.4 * max(0.0, dot(Tn, SunDir)))
                : GetSky(RayDir, SunDir, MoonDir);
            Lit = mix(Behind, Lit, clamp(1.0 - Transparency, 0.08, 1.0));
        }

        float FogFactor = 1.0 - exp(-MinT * 0.0016);
        FinalColor = mix(Lit, GetSky(RayDir, SunDir, MoonDir), FogFactor);

        if (HighlightEnabled > 0.5 && Boxes[HitIndex].IsHighlighted > 0.5) {
            FinalColor = mix(FinalColor, HighlightFillColor, clamp(HighlightFillAlpha, 0.0, 0.9));
        }
    } else {
        FinalColor = GetSky(RayDir, SunDir, MoonDir);
    }

    // Adornments (unlit)
    if (AdornCount > 0) {
        float At = 1e9;
        int Ai = -1;
        vec3 An = vec3(0.0);
        for (int I = 0; I < AdornCount; I++) {
            vec3 N;
            // treat adorn as box
            float T = IntersectBox(CameraPos, RayDir, AdornBoxes[I].Position, AdornBoxes[I].Size * 0.5, N);
            if (T > 0.001 && T < At) { At = T; Ai = I; An = N; }
        }
        if (Ai >= 0) {
            vec3 ac = AdornBoxes[Ai].Color;
            float a = clamp(1.0 - AdornBoxes[Ai].Transparency, 0.1, 1.0);
            float facing = 0.55 + 0.45 * max(0.0, dot(An, -RayDir));
            FinalColor = mix(FinalColor, ac * facing, a);
        }
    }

    // Simple tonemap
    vec3 Mapped = FinalColor * 0.9;
    Mapped = Mapped / (Mapped + vec3(0.9));
    Mapped = pow(max(Mapped, vec3(0.0)), vec3(1.0 / 2.2));
    return vec4(clamp(Mapped, 0.0, 1.0), 1.0);
}