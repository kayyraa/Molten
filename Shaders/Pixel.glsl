#pragma language glsl3

struct Box {
    vec3 Position;
    vec3 Size;
    vec3 Orientation; // Euler radians (X, Y, Z) ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬úΓö£┬║╬ô├╢┬ú╬ô├▓├│ object rotation
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

// Apply R = Rz*Ry*Rx to vector (world from local)
vec3 RotXYZ(vec3 v, vec3 e) {
    float cx = cos(e.x), sx = sin(e.x);
    float cy = cos(e.y), sy = sin(e.y);
    float cz = cos(e.z), sz = sin(e.z);
    // Rx
    float y1 = v.y * cx - v.z * sx;
    float z1 = v.y * sx + v.z * cx;
    float x1 = v.x;
    // Ry
    float x2 = x1 * cy + z1 * sy;
    float z2 = -x1 * sy + z1 * cy;
    float y2 = y1;
    // Rz
    float x3 = x2 * cz - y2 * sz;
    float y3 = x2 * sz + y2 * cz;
    return vec3(x3, y3, z2);
}

// Apply R^T (local from world)
vec3 RotXYZInv(vec3 v, vec3 e) {
    float cx = cos(e.x), sx = sin(e.x);
    float cy = cos(e.y), sy = sin(e.y);
    float cz = cos(e.z), sz = sin(e.z);
    // Rz^T
    float x1 = v.x * cz + v.y * sz;
    float y1 = -v.x * sz + v.y * cz;
    float z1 = v.z;
    // Ry^T
    float x2 = x1 * cy - z1 * sy;
    float z2 = x1 * sy + z1 * cy;
    float y2 = y1;
    // Rx^T
    float y3 = y2 * cx + z2 * sx;
    float z3 = -y2 * sx + z2 * cx;
    return vec3(x2, y3, z3);
}

// Triangle pool: each triangle = 3 consecutive vec4 (xyz = vertex, local space)
// World position = Boxes[i].Position + localVertex
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
uniform int PassIndex;
uniform float FarPlane;
uniform Image PrevPass;

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
uniform float CloudCover;
uniform float CloudDensity;
uniform vec3 CloudColor;
uniform float GlobalShadows;
uniform float Time;

uniform float HighlightEnabled;
uniform vec3  HighlightFillColor;
uniform vec3  HighlightOutlineColor;
uniform float HighlightFillAlpha;
uniform float HighlightOutlineAlpha;

uniform sampler2D GlobalTextures[16];

const int GiSamples = 4;
const float GiStrength = 0.85;
const int ReflectionSamplesMax = 1;
const int SoftShadowSamples = 2;
const int PointLightShadowSamples = 2;
const int MaxPathDepth = 2;
const int GlassExtraSamples = 1;

vec4 SampleTexture(float Index, vec2 Uv) {
    int Idx = int(Index);
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
        else if (A.y > A.z)         N = vec3(0.0, sign(Local.y), 0.0);
        else                        N = vec3(0.0, 0.0, sign(Local.z));
    }

    if (dot(Rd, N) > 0.0) N = -N;
    Normal = N;
    return T;
}

float IntersectSphere(vec3 Ro, vec3 Rd, vec3 Center, vec3 Size, out vec3 Normal) {
    float Radius = min(Size.x, min(Size.y, Size.z)) * 0.5;
    vec3 Oc = Ro - Center;
    float B = dot(Oc, Rd);
    float C = dot(Oc, Oc) - Radius * Radius;
    float H = B * B - C;
    if (H < 0.0) {
        Normal = vec3(0.0);
        return -1.0;
    }
    H = sqrt(H);
    float T = -B - H;
    if (T < 0.0) T = -B + H;
    if (T < 0.0) {
        Normal = vec3(0.0);
        return -1.0;
    }
    vec3 Hit = Ro + Rd * T;
    Normal = normalize(Hit - Center);
    return T;
}

float IntersectCylinder(vec3 Ro, vec3 Rd, vec3 Center, vec3 Size, out vec3 Normal) {
    float Radius = min(Size.x, Size.z) * 0.5;
    float HalfH = Size.y * 0.5;

    vec2 Oc = Ro.xz - Center.xz;
    vec2 Rd2 = Rd.xz;
    float A = dot(Rd2, Rd2);
    float B = dot(Oc, Rd2);
    float C = dot(Oc, Oc) - Radius * Radius;

    float TSide = -1.0;
    vec3 NSide = vec3(0.0);

    if (A > 1e-8) {
        float H = B * B - A * C;
        if (H >= 0.0) {
            H = sqrt(H);
            float T0 = (-B - H) / A;
            float T1 = (-B + H) / A;
            if (T0 > T1) { float Tmp = T0; T0 = T1; T1 = Tmp; }

            float Y0 = Ro.y + Rd.y * T0;
            if (T0 > 0.0 && abs(Y0 - Center.y) <= HalfH) {
                TSide = T0;
                vec3 Hit = Ro + Rd * T0;
                NSide = normalize(vec3(Hit.x - Center.x, 0.0, Hit.z - Center.z));
            } else {
                float Y1 = Ro.y + Rd.y * T1;
                if (T1 > 0.0 && abs(Y1 - Center.y) <= HalfH) {
                    TSide = T1;
                    vec3 Hit = Ro + Rd * T1;
                    NSide = normalize(vec3(Hit.x - Center.x, 0.0, Hit.z - Center.z));
                }
            }
        }
    }

    float TCap = -1.0;
    vec3 NCap = vec3(0.0);

    if (abs(Rd.y) > 1e-8) {
        for (int Cap = 0; Cap < 2; Cap++) {
            float YPlane = Center.y + (Cap == 0 ? HalfH : -HalfH);
            float T = (YPlane - Ro.y) / Rd.y;
            if (T > 0.0 && (TCap < 0.0 || T < TCap)) {
                vec3 Hit = Ro + Rd * T;
                vec2 D = Hit.xz - Center.xz;
                if (dot(D, D) <= Radius * Radius) {
                    TCap = T;
                    NCap = vec3(0.0, Cap == 0 ? 1.0 : -1.0, 0.0);
                }
            }
        }
    }

    if (TSide < 0.0 && TCap < 0.0) {
        Normal = vec3(0.0);
        return -1.0;
    }

    if (TSide < 0.0 || (TCap > 0.0 && TCap < TSide)) {
        Normal = NCap;
        return TCap;
    }
    Normal = NSide;
    return TSide;
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

// Roblox-style CornerWedge: AABB clipped by two slope planes meeting at peak (-hx,+hy,+hz)
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

// M╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├╣╬ô├╢┬ú╬ô├╢├▒╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝╬ô├▓┬Ñ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝Γö£├ªΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥╬ô├╢┬ú╬ô├▓├ªΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£├Ñ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬ú╬ô├╢├⌐╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£┬¬╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├╣╬ô├╢┬ú╬ô├╢├▒╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬ú╬ô├«├ë╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬ú╬ô├╢├⌐╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝╬ô├▓┬Ñ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝Γö£├ªΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥╬ô├╢┬ú╬ô├▓├ªΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£ΓöñΓò¼├┤Γö£ΓòóΓö¼├║╬ô├╢┬╝Γö¼┬╝╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├╣╬ô├╢┬ú╬ô├╢├▒╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝╬ô├▓┬Ñ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝Γö£├ªΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥╬ô├╢┬ú╬ô├▓├ªΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£├Ñ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬ú╬ô├╢├⌐╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£┬¬╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬ú╬ô├▓├║╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬ú╬ô├╗├å╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬ú╬ô├╢├⌐╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£┬¬╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬ú╬ô├╢├⌐╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬úΓö¼┬╜╬ô├╢┬úΓö£┬╜llerΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£ΓöñΓò¼├┤Γö£ΓòóΓö¼Γò¥Γò¼├┤Γö£ΓûôΓö¼├æ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬ú╬ô├╗├åΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥╬ô├╢┬ú╬ô├▓├ªΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓòúΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥Γò¼├┤Γö£ΓûôΓö¼├æΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£ΓöñΓò¼├┤Γö£ΓòóΓö¼Γò¥╬ô├╢┬úΓö£┬¬╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬ú╬ô├╢├⌐╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£┬¬╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬ú╬ô├╢├⌐╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├╣╬ô├╢┬úΓö£├æΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£ΓöñΓò¼├┤Γö£ΓòóΓö¼Γò¥Γò¼├┤Γö£ΓûôΓö¼├æ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬ú╬ô├╗├åΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥╬ô├╢┬ú╬ô├▓├ªΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£ΓöñΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓîÉΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥Γò¼├┤Γö£ΓûôΓö¼├æ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬úΓö¼┬¼╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓûÆ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬ú╬ô├╢├⌐╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝╬ô├▓┬ÑΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£┬¬Γò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥Γò¼├┤Γö£ΓûôΓö¼├æΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£ΓöñΓò¼├┤Γö£ΓòóΓö¼├║╬ô├╢┬╝Γö¼┬╝Γò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£ΓöñΓò¼├┤Γö£ΓòóΓö¼Γò¥Γò¼├┤Γö£ΓûôΓö¼├æ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬ú╬ô├╗├åΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥╬ô├╢┬ú╬ô├▓├ªΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£ΓöñΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓîÉΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥Γò¼├┤Γö£ΓûôΓö¼├æ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├╗├┤╬ô├╢┬úΓö¼┬¼Γò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£ΓöñΓò¼├┤Γö£ΓòóΓö¼Γò¥Γò¼├┤Γö£ΓûôΓö¼├æ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬╝Γö£Γòæ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬ú╬ô├▓├│╬ô├╢┬ú╬ô├╗├åΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥╬ô├╢┬ú╬ô├▓├ªΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòùΓö£ΓöñΓò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓòóΓö£ΓîÉΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓöéΓò¼├┤Γö£ΓòóΓö¼Γò¥╬ô├╢┬ú╬ô├▓├ªΓò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║Γò¼├┤Γö£ΓûôΓö£ΓòúΓò¼├┤Γö£ΓòóΓö¼├║╬ô├╢┬úΓö£├ªTrumbore triangle intersection (local-space verts, world Pos offset)
float IntersectTriangle(vec3 Ro, vec3 Rd, vec3 A, vec3 B, vec3 C, out vec3 Normal) {
    vec3 E1 = B - A;
    vec3 E2 = C - A;
    vec3 P = cross(Rd, E2);
    float Det = dot(E1, P);
    if (abs(Det) < 1e-8) return -1.0;
    float InvDet = 1.0 / Det;
    vec3 T = Ro - A;
    float U = dot(T, P) * InvDet;
    if (U < 0.0 || U > 1.0) return -1.0;
    vec3 Q = cross(T, E1);
    float V = dot(Rd, Q) * InvDet;
    if (V < 0.0 || U + V > 1.0) return -1.0;
    float Dist = dot(E2, Q) * InvDet;
    if (Dist < 1e-5) return -1.0;
    Normal = normalize(cross(E1, E2));
    if (dot(Normal, Rd) > 0.0) Normal = -Normal;
    return Dist;
}

// Mesh intersection: AABB broadphase then triangle tests from TriPool
float IntersectMesh(int I, vec3 Ro, vec3 Rd, out vec3 Normal) {
    vec3 Pos = Boxes[I].Position;
    vec3 Half = Boxes[I].Size * 0.5;
    // Broadphase AABB
    vec3 TmpN;
    float TBox = IntersectBox(Ro, Rd, Pos, Half, TmpN);
    if (TBox < 0.0) return -1.0;

    int Start = int(Boxes[I].TriStart + 0.5);
    int Count = int(Boxes[I].TriCount + 0.5);
    float Best = 1e9;
    vec3 BestN = vec3(0.0);
    bool Hit = false;

    for (int T = 0; T < 32; T++) {
        if (T >= Count) break;
        int Base = (Start + T) * 3;
        if (Base + 2 >= TriPoolCount) break;
        vec3 A = TriPool[Base].xyz + Pos;
        vec3 B = TriPool[Base + 1].xyz + Pos;
        vec3 C = TriPool[Base + 2].xyz + Pos;
        vec3 TN;
        float Tt = IntersectTriangle(Ro, Rd, A, B, C, TN);
        if (Tt > 0.001 && Tt < Best) {
            Best = Tt;
            BestN = TN;
            Hit = true;
        }
    }
    if (!Hit) return -1.0;
    Normal = BestN;
    return Best;
}


float IntersectCone(vec3 Ro, vec3 Rd, vec3 Pos, vec3 Size, out vec3 Normal) {
    float R = min(Size.x, Size.z) * 0.5;
    float H = max(Size.y, 0.001);
    vec3 O = Ro - Pos;
    O.y += H * 0.5;
    float k = R / H;
    float k2 = k * k;
    float a = Rd.x * Rd.x + Rd.z * Rd.z - k2 * Rd.y * Rd.y;
    float b = 2.0 * (O.x * Rd.x + O.z * Rd.z - k2 * O.y * Rd.y);
    float c = O.x * O.x + O.z * O.z - k2 * O.y * O.y;
    float disc = b * b - 4.0 * a * c;
    float Best = 1e9;
    vec3 BestN = vec3(0.0);
    bool Hit = false;
    if (disc >= 0.0 && abs(a) > 1e-8) {
        float sdisc = sqrt(disc);
        for (int i = 0; i < 2; i++) {
            float t = (-b + (i == 0 ? -sdisc : sdisc)) / (2.0 * a);
            if (t > 0.001) {
                vec3 p = O + Rd * t;
                if (p.y >= 0.0 && p.y <= H) {
                    if (t < Best) {
                        Best = t;
                        BestN = normalize(vec3(p.x, -k2 * p.y, p.z));
                        Hit = true;
                    }
                }
            }
        }
    }
    if (abs(Rd.y) > 1e-6) {
        float t = -O.y / Rd.y;
        if (t > 0.001) {
            vec3 p = O + Rd * t;
            if (p.x * p.x + p.z * p.z <= R * R && t < Best) {
                Best = t;
                BestN = vec3(0.0, -1.0, 0.0);
                Hit = true;
            }
        }
    }
    if (!Hit) return -1.0;
    if (dot(BestN, Rd) > 0.0) BestN = -BestN;
    Normal = BestN;
    return Best;
}

float IntersectShape(int I, vec3 Ro, vec3 Rd, out vec3 Normal) {
    int Shape = int(Boxes[I].ShapeType + 0.5);
    vec3 Pos  = Boxes[I].Position;
    vec3 Size = Boxes[I].Size;
    vec3 Ori  = Boxes[I].Orientation;

    // Rotate ray into local space when orientation is non-zero
    float oa = abs(Ori.x) + abs(Ori.y) + abs(Ori.z);
    vec3 RoL = Ro;
    vec3 RdL = Rd;
    if (oa > 1e-5) {
        vec3 off = RotXYZInv(Ro - Pos, Ori);
        RoL = Pos + off;
        RdL = RotXYZInv(Rd, Ori);
    }

    float T;
    if (Shape == 1) {
        T = IntersectSphere(RoL, RdL, Pos, Size, Normal);
    } else if (Shape == 2) {
        T = IntersectCylinder(RoL, RdL, Pos, Size, Normal);
    } else if (Shape == 3) {
        T = IntersectWedge(RoL, RdL, Pos, Size, Normal);
    } else if (Shape == 4) {
        T = IntersectCone(RoL, RdL, Pos, Size, Normal);
    } else if (Shape == 5) {
        T = IntersectCornerWedge(RoL, RdL, Pos, Size, Normal);
    } else if (Shape >= 10 && Boxes[I].TriCount > 0.5) {
        T = IntersectMesh(I, RoL, RdL, Normal);
    } else {
        T = IntersectBox(RoL, RdL, Pos, Size * 0.5, Normal);
    }

    if (T > 0.0 && oa > 1e-5) {
        Normal = normalize(RotXYZ(Normal, Ori));
    }
    return T;
}

int TraceScene(vec3 Ro, vec3 Rd, int SkipIndex, out float OutT, out vec3 OutNormal) {
    float MinT = 1e9;
    vec3 HitNormal = vec3(0.0);
    int HitIndex = -1;

    for (int I = 0; I < BoxCount; I++) {
        if (I == SkipIndex) continue;
        vec3 N;
        float T = IntersectShape(I, Ro, Rd, N);
        // Accept both front and back faces so transmission can exit glass
        if (T > 0.001 && T < MinT) {
            MinT = T;
            HitNormal = N;
            HitIndex = I;
        }
    }

    OutT = MinT;
    OutNormal = HitNormal;
    return HitIndex;
}

int TraceAlwaysOnTop(vec3 Ro, vec3 Rd, out float OutT, out vec3 OutNormal) {
    float MinT = 1e9;
    vec3 HitNormal = vec3(0.0);
    int HitIndex = -1;

    for (int I = 0; I < BoxCount; I++) {
        if (Boxes[I].AlwaysOnTop < 0.5) continue;
        vec3 N;
        float T = IntersectShape(I, Ro, Rd, N);
        if (T > 0.001 && T < MinT) {
            MinT = T;
            HitNormal = N;
            HitIndex = I;
        }
    }

    OutT = MinT;
    OutNormal = HitNormal;
    return HitIndex;
}

int TraceAdornments(vec3 Ro, vec3 Rd, out float OutT, out vec3 OutNormal) {
    float MinT = 1e9;
    vec3 HitNormal = vec3(0.0);
    int HitIndex = -1;
    for (int I = 0; I < ADORN_MAX; I++) {
        if (I >= AdornCount) break;
        vec3 N;
        // reuse IntersectShape logic on AdornBoxes via local copy fields
        int Shape = int(AdornBoxes[I].ShapeType + 0.5);
        vec3 Pos = AdornBoxes[I].Position;
        vec3 Size = AdornBoxes[I].Size;
        float T = -1.0;
        if (Shape == 1) T = IntersectSphere(Ro, Rd, Pos, Size, N);
        else if (Shape == 2) T = IntersectCylinder(Ro, Rd, Pos, Size, N);
        else if (Shape == 3) T = IntersectWedge(Ro, Rd, Pos, Size, N);
        else if (Shape == 4) T = IntersectCone(Ro, Rd, Pos, Size, N);
        else T = IntersectBox(Ro, Rd, Pos, Size * 0.5, N);
        if (T > 0.001 && T < MinT) {
            MinT = T;
            HitNormal = N;
            HitIndex = I;
        }
    }
    OutT = MinT;
    OutNormal = HitNormal;
    return HitIndex;
}



vec3 GetAtmosphere(vec3 Rd, vec3 SunDir) {
    vec3 DaySky   = mix(vec3(0.40, 0.60, 0.90), vec3(0.12, 0.22, 0.50), max(0.0, Rd.y));
    vec3 NightSky = mix(vec3(0.04, 0.05, 0.09), vec3(0.005, 0.008, 0.02), max(0.0, Rd.y));
    float SunFactor = clamp(SunDir.y, -0.25, 0.25) / 0.5 + 0.5;
    return mix(NightSky, DaySky, SunFactor);
}

vec3 GetSkyBase(vec3 Rd, vec3 SunDir, vec3 MoonDir) {
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

    return Sky;
}

float HashCloud(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float NoiseCloud(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = HashCloud(i);
    float b = HashCloud(i + vec2(1.0, 0.0));
    float c = HashCloud(i + vec2(0.0, 1.0));
    float d = HashCloud(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float FbmCloud2(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * NoiseCloud(p);
        p = p * 2.05 + vec2(11.3, 7.1);
        a *= 0.5;
    }
    return v;
}

vec3 EvalClouds(vec3 Rd, vec3 SunDir, float time, out float outAlpha) {
    outAlpha = 0.0;
    if (CloudCover < 0.01 || Rd.y < 0.015) return vec3(0.0);

    float horizon = smoothstep(0.015, 0.22, Rd.y);
    vec2 uv = Rd.xz / max(Rd.y, 0.08);
    uv *= mix(0.55, 1.35, CloudDensity);
    uv += vec2(time * 0.01, time * 0.006);

    float n = FbmCloud2(uv);
    float n2 = FbmCloud2(uv * 1.7 + vec2(3.1, 5.7));
    float shape = n * 0.7 + n2 * 0.3;

    float threshold = 1.0 - clamp(CloudCover, 0.0, 1.0) * 0.88;
    float dens = smoothstep(threshold, threshold + 0.18 + CloudDensity * 0.25, shape);
    dens *= horizon;
    dens = clamp(dens * mix(0.5, 1.2, CloudDensity), 0.0, 1.0);
    if (dens < 0.01) return vec3(0.0);

    float thickness = dens * mix(0.4, 1.0, CloudDensity);
    vec3 thinCol = mix(vec3(0.95, 0.96, 0.98), CloudColor, 0.25);
    vec3 thickCol = mix(vec3(0.48, 0.50, 0.55), CloudColor * 0.65, 0.35);
    vec3 albedo = mix(thinCol, thickCol, clamp(thickness * 1.15, 0.0, 1.0));

    float sunUp = clamp(SunDir.y * 0.5 + 0.5, 0.0, 1.0);
    float sunFacing = pow(max(0.0, dot(normalize(vec3(Rd.x, max(Rd.y, 0.05), Rd.z)), SunDir)), 2.0);
    float selfShadow = mix(1.0, 0.45, thickness * 0.85);
    vec3 lit = albedo * (0.40 + 0.35 * sunUp + 0.45 * sunFacing * selfShadow);
    float silver = pow(max(0.0, dot(Rd, SunDir)), 6.0) * (1.0 - thickness) * 0.4;
    lit += vec3(1.1, 1.05, 0.95) * silver * sunUp;

    outAlpha = dens * dens * (3.0 - 2.0 * dens);
    outAlpha = clamp(outAlpha, 0.0, 0.92);
    return lit;
}

vec3 GetSky(vec3 Rd, vec3 SunDir, vec3 MoonDir) {
    vec3 Sky = GetSkyBase(Rd, SunDir, MoonDir);
    float SunFactor = clamp(SunDir.y, -0.25, 0.25) / 0.5 + 0.5;

    float cAlpha = 0.0;
    vec3 cCol = EvalClouds(Rd, SunDir, Time, cAlpha);
    if (cAlpha > 0.001) {
        Sky = mix(Sky, cCol, cAlpha);
        float sunDot = max(0.0, dot(Rd, SunDir));
        float sunAtten = 1.0 - cAlpha * mix(0.3, 0.85, CloudDensity);
        Sky *= mix(1.0, sunAtten, smoothstep(0.25, 0.95, sunDot));
    }

    if (SunFactor < 0.65 && Rd.y > 0.04) {
        vec3 P = floor(Rd * 520.0);
        float StarVal = fract(sin(dot(P, vec3(127.1, 311.7, 74.7))) * 43758.5453);
        if (StarVal > 0.995) {
            float Intensity = pow((StarVal - 0.995) / 0.005, 2.0);
            float starVis = (1.0 - SunFactor) * (1.0 - cAlpha);
            Sky += vec3(1.5, 1.6, 1.9) * Intensity * starVis * smoothstep(0.04, 0.22, Rd.y) * 22.0;
        }
    }
    return Sky;
}

vec3 GetSkyForBounce(vec3 Rd, vec3 SunDir, vec3 MoonDir) {
    return GetSkyBase(Rd, SunDir, MoonDir);
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

vec2 GetBoxUvOriented(vec3 HitPos, vec3 BoxPos, vec3 BoxSize, vec3 Normal, vec3 Ori) {
    vec3 Local = HitPos - BoxPos;
    if (abs(Ori.x) + abs(Ori.y) + abs(Ori.z) > 1e-5) {
        Local = RotXYZInv(Local, Ori);
    }
    Local = Local / max(BoxSize, vec3(1e-5));
    vec2 Uv = vec2(0.0);
    if (abs(Normal.x) > 0.5) {
        Uv = Normal.x > 0.0 ? Local.zy : -Local.zy;
    } else if (abs(Normal.y) > 0.5) {
        Uv = Normal.y > 0.0 ? Local.xz : -Local.xz;
    } else {
        Uv = Normal.z > 0.0 ? -Local.xy : Local.xy;
    }
    return Uv + 0.5;
}

vec3 PerturbNormal(vec3 Normal, vec3 Tangent, vec3 Bitangent, vec3 SampledNormal) {
    vec3 NormalMap = SampledNormal * 2.0 - 1.0;
    mat3 Tbn = mat3(normalize(Tangent), normalize(Bitangent), normalize(Normal));
    return normalize(Tbn * NormalMap);
}

float Hash13(vec3 P) {
    P = fract(P * 0.1031);
    P += dot(P, P.yzx + 33.33);
    return fract((P.x + P.y) * P.z);
}

vec2 Hash23(vec3 P) {
    return vec2(Hash13(P), Hash13(P + 17.31));
}

vec3 CosineSampleHemisphere(vec3 N, vec2 Rnd) {
    float R = sqrt(Rnd.x);
    float Theta = 6.28318530718 * Rnd.y;
    float X = R * cos(Theta);
    float Y = R * sin(Theta);
    float Z = sqrt(max(0.0, 1.0 - Rnd.x));

    vec3 Up = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 Tangent = normalize(cross(Up, N));
    vec3 Bitangent = cross(N, Tangent);

    return normalize(Tangent * X + Bitangent * Y + N * Z);
}

vec3 RoughenReflection(vec3 R, vec3 N, float Roughness, vec2 Rnd) {
    float Rr = clamp(Roughness, 0.0, 1.0);
    if (Rr <= 0.001) return R;

    vec3 HemiR = CosineSampleHemisphere(R, Rnd);
    vec3 HemiN = CosineSampleHemisphere(N, Rnd);

    float GlossyBlend  = clamp(Rr * 2.0, 0.0, 1.0);
    float DiffuseBlend = clamp(Rr * 2.0 - 1.0, 0.0, 1.0);

    vec3 Glossy   = normalize(mix(R, HemiR, GlossyBlend));
    vec3 Scattered = normalize(mix(Glossy, HemiN, DiffuseBlend));

    if (dot(Scattered, N) < 0.0) return mix(R, HemiN, DiffuseBlend);
    return Scattered;
}

float SchlickFresnel(float CosTheta, float F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - CosTheta, 0.0, 1.0), 5.0);
}

float DistributionGGX(float NdotH, float Roughness) {
    float A = Roughness * Roughness;
    float A2 = A * A;
    float D = (NdotH * NdotH) * (A2 - 1.0) + 1.0;
    return A2 / (3.14159265 * D * D + 1e-5);
}

vec3 ShadeHitFast(int HitIndex, vec3 HitPos, vec3 HitNormal, vec3 SunDir, vec3 MoonDir) {
    vec3 BaseColor = Boxes[HitIndex].Color;

    vec2 PartUv = GetBoxUvOriented(HitPos, Boxes[HitIndex].Position, Boxes[HitIndex].Size, HitNormal, Boxes[HitIndex].Orientation);
    vec4 TexColor = SampleTexture(Boxes[HitIndex].ColorTexIndex, PartUv);
    BaseColor *= TexColor.rgb;

    float PartAlphaFast = 1.0 - Boxes[HitIndex].Transparency;
    BaseColor *= mix(1.0, PartAlphaFast, 0.85);
    if (Boxes[HitIndex].HasDecal > 0.5 && HitNormal.y > 0.5) {
        vec3 DecalLocal = HitPos - Boxes[HitIndex].Position;
            vec3 OriD = Boxes[HitIndex].Orientation;
            if (abs(OriD.x) + abs(OriD.y) + abs(OriD.z) > 1e-5) {
                DecalLocal = RotXYZInv(DecalLocal, OriD);
            }
            vec2 DecalUv = DecalLocal.xz / max(Boxes[HitIndex].UvStuds, vec2(0.001)) + Boxes[HitIndex].UvOffset;
        vec4 DecalSample = SampleTexture(Boxes[HitIndex].DecalTexIndex, fract(DecalUv));
        float DA = DecalSample.a * Boxes[HitIndex].DecalAlpha;
        BaseColor = mix(BaseColor, DecalSample.rgb * Boxes[HitIndex].DecalColor, DA);
    }

    float SunDiff  = max(0.0, dot(HitNormal, SunDir));
    float MoonDiff = max(0.0, dot(HitNormal, MoonDir));
    float Ambient  = 0.22;
    float Day = SunDir.y > 0.0 ? 1.0 : 0.12;

    vec3 Light = (SunDiff * vec3(1.25, 1.15, 1.0) * 2.1 * Day) +
                 (MoonDiff * vec3(0.18, 0.25, 0.55)) +
                 Ambient;

    float Reflectivity = Boxes[HitIndex].Reflectivity;
    vec3 Diffuse = BaseColor * Light * (1.0 - Reflectivity * 0.75);

    if (Reflectivity > 0.001) {
        vec3 Tint = mix(vec3(1.0), BaseColor, Reflectivity * 0.6);
        vec3 EnvApprox = GetSkyForBounce(normalize(HitNormal + vec3(0.0, 0.5, 0.0)), SunDir, -SunDir);
        Diffuse += EnvApprox * Tint * Reflectivity * 0.5;
    }

    return Diffuse;
}

vec3 SampleGi(vec3 HitPos, vec3 HitNormal, int HitIndex, vec3 SunDir, vec3 MoonDir, vec3 Seed) {
    vec2 Rnd = Hash23(Seed);
    vec3 BounceDir = CosineSampleHemisphere(HitNormal, Rnd);

    float Bt;
    vec3 Bn;
    int BounceIndex = TraceScene(HitPos + HitNormal * 0.04, BounceDir, HitIndex, Bt, Bn);

    if (BounceIndex != -1) {
        vec3 BouncePos = HitPos + BounceDir * Bt;
        vec3 BounceLit = ShadeHitFast(BounceIndex, BouncePos, Bn, SunDir, MoonDir);
        float Roughness = Boxes[BounceIndex].Roughness;
        float Proximity = 1.0 / (1.0 + Bt * Bt * 1.8);
        return BounceLit * (1.0 + Roughness * Proximity * 2.5);
    }
    return GetSkyForBounce(BounceDir, SunDir, MoonDir);
}

vec2 VogelDisk(int Index, int Count, float Jitter) {
    float Golden = 2.399963229728653;
    float R = sqrt((float(Index) + 0.5) / float(Count));
    float Theta = float(Index) * Golden + Jitter;
    return vec2(cos(Theta), sin(Theta)) * R;
}

float OccluderDistance(vec3 Origin, vec3 Dir, int SkipIndex, float MaxDist) {
    float Closest = MaxDist;
    bool Hit = false;
    float MinT = max(0.08, MaxDist * 0.00015);

    for (int I = 0; I < BoxCount; I++) {
        if (I == SkipIndex) continue;
        if (Boxes[I].CastShadows < 0.5) continue;
        vec3 Sn;
        float St = IntersectShape(I, Origin, Dir, Sn);
        if (St > MinT && St < Closest) {
            Closest = St;
            Hit = true;
        }
    }
    return Hit ? Closest : -1.0;
}

float SoftSunShadow(vec3 HitPos, vec3 N, vec3 SunDir, int SkipIndex, vec3 Seed) {
    // Hard shadow (single ray, no PCSS)
    if (GlobalShadows < 0.5) return 1.0;
    if (SunDir.y <= 0.0) return 0.2;

    // Bias off the surface toward the light
    vec3 Origin = HitPos + normalize(N) * 0.08 + SunDir * 0.05;

    for (int I = 0; I < BoxCount; I++) {
        if (I == SkipIndex) continue;
        // Ignore nearly invisible surfaces as occluders
        if (Boxes[I].Transparency > 0.85) continue;
        vec3 Sn;
        float St = IntersectShape(I, Origin, SunDir, Sn);
        if (St > 0.02 && St < 1000.0) {
            // Sharp umbra ╬ô├▓┬╝Γö£Γöñ╬ô├╢┬úΓö£┬║╬ô├╢┬ú╬ô├▓├│ fully blocked (tiny residual so it is not pure black)
            return 0.08;
        }
    }
    return 1.0;
}

vec3 EvaluatePointLights(vec3 HitPos, vec3 N, vec3 ViewDir, float Roughness, int SkipIndex, vec3 Seed) {
    vec3 Accum = vec3(0.0);
    float SmoothSpec = mix(48.0, 6.0, clamp(Roughness, 0.0, 1.0));

    for (int Li = 0; Li < 8; Li++) {
        if (Li >= LightCount) break;

        vec3 ToLight = Lights[Li].Position - HitPos;
        float DistSq = dot(ToLight, ToLight);
        float Range = max(Lights[Li].Range, 0.01);
        float RangeSq = Range * Range;

        if (DistSq >= RangeSq || DistSq < 0.0001) continue;

        float Dist = sqrt(DistSq);
        vec3 L = ToLight * (1.0 / Dist);
        float NdotL = dot(N, L);
        float DiffuseFactor = NdotL * 0.5 + 0.5;
        DiffuseFactor = DiffuseFactor * DiffuseFactor;

        float Normalized = Dist / Range;
        float Atten = 1.0 - Normalized;
        Atten = Atten * Atten * (3.0 - 2.0 * Atten);
        Atten /= (1.0 + DistSq * 0.008);
        Atten = clamp(Atten, 0.0, 3.0);

        float Shadow = 1.0;
        if (Lights[Li].Shadows > 0.5) {
            float Bias = max(0.4, Dist * 0.006);
            vec3 Origin = HitPos + N * Bias;
            float MaxDist = Dist - Bias * 2.0;

            if (MaxDist > 0.3) {
                float Blocker = OccluderDistance(Origin, L, SkipIndex, MaxDist);
                if (Blocker > 0.0) {
                    Shadow = 0.15;
                }
            }
        }

        float Intensity = Lights[Li].Brightness * 0.28;
        vec3 LightCol = Lights[Li].Color * Intensity;
        vec3 Diffuse = LightCol * DiffuseFactor * Atten;

        float SpecNdotL = max(0.0, NdotL);
        vec3 H = normalize(L + ViewDir);
        float NdotH = max(0.0, dot(N, H));
        float Spec = pow(NdotH, SmoothSpec) * (1.0 - Roughness * 0.7) * SpecNdotL;
        Spec = min(Spec, 2.5);
        vec3 Specular = LightCol * Spec * Atten * 0.12;

        Accum += (Diffuse + Specular) * Shadow;
    }
    return Accum;
}

// ---------------------------------------------------------------------------
// Local direct shading (used by path continuation)
// ---------------------------------------------------------------------------
vec3 ResolveAlbedo(int HitIndex, vec3 HitPos, vec3 N) {
    vec3 BaseColor = Boxes[HitIndex].Color;
    vec2 PartUv = GetBoxUvOriented(HitPos, Boxes[HitIndex].Position, Boxes[HitIndex].Size, N, Boxes[HitIndex].Orientation);
    vec4 TexColor = SampleTexture(Boxes[HitIndex].ColorTexIndex, PartUv);
    BaseColor *= TexColor.rgb;
    float PartAlpha = 1.0 - Boxes[HitIndex].Transparency;
    BaseColor *= mix(1.0, PartAlpha, 0.85);
    if (Boxes[HitIndex].HasDecal > 0.5 && N.y > 0.5) {
        vec3 DecalLocal = HitPos - Boxes[HitIndex].Position;
            vec3 OriD = Boxes[HitIndex].Orientation;
            if (abs(OriD.x) + abs(OriD.y) + abs(OriD.z) > 1e-5) {
                DecalLocal = RotXYZInv(DecalLocal, OriD);
            }
            vec2 DecalUv = DecalLocal.xz / max(Boxes[HitIndex].UvStuds, vec2(0.001)) + Boxes[HitIndex].UvOffset;
        vec4 DecalSample = SampleTexture(Boxes[HitIndex].DecalTexIndex, fract(DecalUv));
        float DA = DecalSample.a * Boxes[HitIndex].DecalAlpha;
        BaseColor = mix(BaseColor, DecalSample.rgb * Boxes[HitIndex].DecalColor, DA);
    }
    return BaseColor;
}

vec3 ShadeDirect(int HitIndex, vec3 HitPos, vec3 N, vec3 SunDir, vec3 MoonDir) {
    vec3 BaseColor = ResolveAlbedo(HitIndex, HitPos, N);
    float Roughness = Boxes[HitIndex].Roughness;
    float Reflectivity = Boxes[HitIndex].Reflectivity;
    float Transparency = Boxes[HitIndex].Transparency;

    float SunDiff  = max(0.0, dot(N, SunDir));
    float MoonDiff = max(0.0, dot(N, MoonDir));
    float Shadow = SoftSunShadow(HitPos, N, SunDir, HitIndex, HitPos * 3.1);
    float Hemi = 0.5 + 0.5 * N.y;
    vec3 SkyAmbient = mix(vec3(0.10, 0.12, 0.16), vec3(0.32, 0.40, 0.52), Hemi) * 0.55;
    float cloudShadeD = 1.0 - clamp(CloudCover * mix(0.35, 0.85, CloudDensity), 0.0, 0.9);
    vec3 SunLight  = SunDiff * vec3(1.50, 1.35, 1.12) * 3.0 * Shadow * cloudShadeD;
    vec3 MoonLight = MoonDiff * vec3(0.16, 0.22, 0.42) * 0.9;
    vec3 PointLit = EvaluatePointLights(HitPos, N, normalize(CameraPos - HitPos), Roughness, HitIndex, HitPos);

    float Body = (1.0 - Reflectivity * 0.85);
    vec3 Lit = BaseColor * (SunLight + MoonLight + SkyAmbient + 0.15 + PointLit) * Body;

    if (Reflectivity > 0.001) {
        vec3 ViewDir = normalize(CameraPos - HitPos);
        vec3 R = reflect(-ViewDir, N);
        float Rt; vec3 Rn;
        int RIdx = TraceScene(HitPos + N * 0.04, R, HitIndex, Rt, Rn);
        vec3 Rcol = (RIdx >= 0)
            ? ResolveAlbedo(RIdx, HitPos + R * Rt, Rn) * (0.35 + 0.65 * max(0.0, dot(Rn, SunDir)))
            : GetSkyForBounce(R, SunDir, MoonDir);
        float blur = clamp(Roughness, 0.0, 1.0);
        Rcol = mix(Rcol, SkyAmbient * 2.0 + BaseColor * 0.15, blur * 0.65);
        float CosTheta = max(0.0, dot(ViewDir, N));
        float F0 = mix(0.04, 0.9, Reflectivity);
        float Fresnel = SchlickFresnel(CosTheta, F0);
        float Amt = Reflectivity * mix(Fresnel, 1.0, Reflectivity);
        Amt *= (1.0 - blur * 0.35);
        Lit += Rcol * mix(vec3(1.0), BaseColor, Reflectivity * 0.35) * Amt;
    }
    return Lit;
}

vec3 EvalHit(int HitIndex, vec3 HitPos, vec3 HitNormal, vec3 Rd,
             vec3 SunDir, vec3 MoonDir, int DepthLeft, vec3 Seed) {
    vec3 BaseColor = ResolveAlbedo(HitIndex, HitPos, HitNormal);
    float Roughness    = Boxes[HitIndex].Roughness;
    float Reflectivity = Boxes[HitIndex].Reflectivity;
    float Refractivity = Boxes[HitIndex].Refractivity;
    float Transparency = Boxes[HitIndex].Transparency;
    bool IsGlass = Transparency > 0.05 || Refractivity > 0.05;

    vec3 N = HitNormal;
    float CosTheta = max(0.0, dot(-Rd, N));

    if (!IsGlass) {
        return ShadeDirect(HitIndex, HitPos, N, SunDir, MoonDir);
    }

    float F0G = mix(0.04, 0.08, clamp(Reflectivity, 0.0, 1.0));
    float Fresnel = SchlickFresnel(CosTheta, F0G);

    float Ior = mix(1.0, 1.45, clamp(Refractivity, 0.0, 1.0));
    vec3 Tdir = Rd;
    if (Refractivity > 0.001) {
        vec3 Refr = refract(Rd, N, 1.0 / Ior);
        if (dot(Refr, Refr) > 1e-6) Tdir = Refr;
    }

    vec3 Throughput = mix(vec3(1.0), BaseColor, clamp((1.0 - Transparency) * 0.25 + Refractivity * 0.15, 0.0, 0.55));
    vec3 Origin = HitPos + Tdir * 0.05;
    vec3 Dir = Tdir;
    int Skip = HitIndex;
    vec3 Behind = GetSkyForBounce(Dir, SunDir, MoonDir);

    for (int Layer = 0; Layer < MaxPathDepth; Layer++) {
        if (Layer >= DepthLeft) break;
        float Tt; vec3 Tn;
        int TIdx = TraceScene(Origin, Dir, Skip, Tt, Tn);
        if (TIdx < 0) {
            Behind = GetSkyForBounce(Dir, SunDir, MoonDir);
            break;
        }
        vec3 Tpos = Origin + Dir * Tt;
        float Tr = Boxes[TIdx].Transparency;
        float Rr = Boxes[TIdx].Refractivity;

        if (Tr < 0.05 && Rr < 0.05) {
            Behind = ShadeDirect(TIdx, Tpos, Tn, SunDir, MoonDir);
            break;
        }

        vec3 Col = ResolveAlbedo(TIdx, Tpos, Tn);
        Throughput *= mix(vec3(1.0), Col, clamp((1.0 - Tr) * 0.25 + Rr * 0.15, 0.0, 0.5));
        if (Rr > 0.001) {
            float I2 = mix(1.0, 1.45, clamp(Rr, 0.0, 1.0));
            vec3 NewD = refract(Dir, Tn, 1.0 / I2);
            if (dot(NewD, NewD) > 1e-6) Dir = NewD;
        }
        Origin = Tpos + Dir * 0.05;
        Skip = TIdx;
        Behind = ShadeDirect(TIdx, Tpos, Tn, SunDir, MoonDir) * (1.0 - Tr) * 0.2;
    }
    Behind *= Throughput;

    vec3 Reflected = vec3(0.0);
    float ReflectAmt = Reflectivity * 0.5 + Fresnel * 0.35;
    if (ReflectAmt > 0.02 && DepthLeft > 0) {
        vec3 R = reflect(Rd, N);
        float Rt; vec3 Rn;
        int RIdx = TraceScene(HitPos + N * 0.05, R, HitIndex, Rt, Rn);
        if (RIdx >= 0) {
            Reflected = ShadeDirect(RIdx, HitPos + R * Rt, Rn, SunDir, MoonDir);
        } else {
            Reflected = GetSkyForBounce(R, SunDir, MoonDir);
        }
        float blur = clamp(Roughness, 0.0, 1.0);
        Reflected = mix(Reflected, Behind * 0.3 + mix(vec3(0.08, 0.09, 0.12), vec3(0.35, 0.42, 0.55), clamp(SunDir.y * 0.5 + 0.5, 0.0, 1.0)), blur * 0.5);
    }

    float TransmitAmt = clamp(max(Transparency, Refractivity * 0.8) * (1.0 - Fresnel * 0.5), 0.0, 1.0);
    ReflectAmt = clamp(ReflectAmt * (1.0 - TransmitAmt * 0.5), 0.0, 1.0);
    vec3 Surface = ShadeDirect(HitIndex, HitPos, N, SunDir, MoonDir) * (1.0 - Transparency) * 0.25;
    return Surface + Behind * TransmitAmt + Reflected * ReflectAmt;
}

vec3 SkyAmbientApprox(vec3 SunDir) {
    float k = clamp(SunDir.y * 0.5 + 0.5, 0.0, 1.0);
    return mix(vec3(0.08, 0.09, 0.12), vec3(0.35, 0.42, 0.55), k);
}

vec3 SampleReflection(vec3 HitPos, vec3 HitNormal, vec3 Incident, int HitIndex,
                       float Roughness, vec3 SunDir, vec3 MoonDir, vec3 Seed, int MaxSamples) {
    vec3 N = HitNormal;
    if (dot(N, Incident) > 0.0) N = -N;
    vec3 R = reflect(Incident, N);
    if (dot(R, N) < 0.0) R = reflect(Incident, HitNormal);

    float Rr = clamp(Roughness, 0.0, 1.0);
    int Samples = (Rr < 0.15) ? 1 : min(MaxSamples, ReflectionSamplesMax);
    Samples = max(Samples, 1);

    vec3 Accum = vec3(0.0);
    for (int S = 0; S < ReflectionSamplesMax; S++) {
        if (S >= Samples) break;
        vec3 SSeed = Seed + vec3(float(S) * 17.9, float(S) * 31.3, float(S) * 7.1);
        vec2 Rnd = Hash23(SSeed);
        vec3 ReflDir = RoughenReflection(R, N, Rr, Rnd);
        if (dot(ReflDir, N) < 0.0) ReflDir = R;

        float Rt; vec3 Rn;
        int RIdx = TraceScene(HitPos + N * 0.05, ReflDir, HitIndex, Rt, Rn);
        if (RIdx >= 0) {
            Accum += ShadeDirect(RIdx, HitPos + ReflDir * Rt, Rn, SunDir, MoonDir);
        } else {
            Accum += GetSkyForBounce(ReflDir, SunDir, MoonDir);
        }
    }
    vec3 Result = Accum / float(Samples);
    if (Rr > 0.01) {
        Result = mix(Result, SkyAmbientApprox(SunDir) + Result * 0.3, Rr * 0.55);
    }
    return Result;
}

vec3 SampleTransmission(vec3 HitPos, vec3 HitNormal, vec3 Incident, int HitIndex,
                         float Transparency, float Refractivity,
                         vec3 SunDir, vec3 MoonDir, vec3 BaseColor) {
    return EvalHit(HitIndex, HitPos, HitNormal, Incident, SunDir, MoonDir, MaxPathDepth, HitPos * 7.1);
}

vec4 effect(vec4 Color, Image Tex, vec2 TextureCoords, vec2 ScreenCoords) {
    vec2 Uv = (ScreenCoords - 0.5 * Resolution) / Resolution.y;
    float TanFov = tan(Fov * 0.5);
    vec3 RayDir = normalize(CameraForward + CameraRight * Uv.x * TanFov - CameraUp * Uv.y * TanFov);

    float MinT;
    vec3 HitNormal;
    int HitIndex = TraceScene(CameraPos, RayDir, -1, MinT, HitNormal);

    float DayAngle = (ClockTime - 6.0) / 24.0 * 6.2831853;
    vec3 SunDir  = normalize(vec3(cos(DayAngle), sin(DayAngle), 0.28));
    vec3 MoonDir = -SunDir;

    vec3 FinalColor = vec3(0.0);

    if (HitIndex != -1) {
        vec3 HitPos = CameraPos + RayDir * MinT;
        vec3 BaseColor = Boxes[HitIndex].Color;

        vec2 PartUv = GetBoxUvOriented(HitPos, Boxes[HitIndex].Position, Boxes[HitIndex].Size, HitNormal, Boxes[HitIndex].Orientation);
        vec4 TexColor = SampleTexture(Boxes[HitIndex].ColorTexIndex, PartUv);
        BaseColor *= TexColor.rgb;

        vec3 Tangent = abs(HitNormal.y) > 0.5 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
        vec3 Bitangent = cross(HitNormal, Tangent);
        vec3 NormalSample = SampleTexture(Boxes[HitIndex].NormalTexIndex, PartUv).rgb;
        vec3 PerturbedNormal = PerturbNormal(HitNormal, Tangent, Bitangent, NormalSample);

        BaseColor *= mix(1.0, 1.0 - Boxes[HitIndex].Transparency, 0.85);
        if (Boxes[HitIndex].HasDecal > 0.5 && HitNormal.y > 0.5) {
            vec3 DecalLocal = HitPos - Boxes[HitIndex].Position;
            vec3 OriD = Boxes[HitIndex].Orientation;
            if (abs(OriD.x) + abs(OriD.y) + abs(OriD.z) > 1e-5) {
                DecalLocal = RotXYZInv(DecalLocal, OriD);
            }
            vec2 DecalUv = DecalLocal.xz / max(Boxes[HitIndex].UvStuds, vec2(0.001)) + Boxes[HitIndex].UvOffset;
            vec4 DecalSample = SampleTexture(Boxes[HitIndex].DecalTexIndex, fract(DecalUv));
            vec3 Tinted = DecalSample.rgb * Boxes[HitIndex].DecalColor;
            float DA = DecalSample.a * Boxes[HitIndex].DecalAlpha;
            BaseColor = mix(BaseColor, Tinted, DA);
        }

        float SunDiff  = max(0.0, dot(PerturbedNormal, SunDir));
        float MoonDiff = max(0.0, dot(PerturbedNormal, MoonDir));
        float Ambient  = 0.18;

        vec3 ShadowSeed = HitPos * 7.1 + vec3(Time, Uv.x * 13.0, Uv.y * 17.0);
        float Shadow = SoftSunShadow(HitPos, PerturbedNormal, SunDir, HitIndex, ShadowSeed);
        vec3 ViewDir = normalize(CameraPos - HitPos);
        vec3 PointLit = EvaluatePointLights(HitPos, PerturbedNormal, ViewDir, Boxes[HitIndex].Roughness, HitIndex, ShadowSeed);

        float Hemi = 0.5 + 0.5 * PerturbedNormal.y;
        float cloudAmb = 1.0 - clamp(CloudCover * CloudDensity * 0.55, 0.0, 0.7);
        vec3 SkyAmbient = mix(vec3(0.10, 0.12, 0.16), vec3(0.32, 0.40, 0.52), Hemi) * 0.60 * cloudAmb;
        float cloudShade = 1.0 - clamp(CloudCover * mix(0.35, 0.85, CloudDensity), 0.0, 0.9);
        vec3 SunLight   = SunDiff * vec3(1.50, 1.35, 1.12) * 3.2 * Shadow * cloudShade;
        vec3 MoonLight  = MoonDiff * vec3(0.16, 0.22, 0.42) * 0.95;
        vec3 DirectLight = SunLight + MoonLight + SkyAmbient * 0.55 + Ambient * 0.22 + PointLit;

        float Roughness    = Boxes[HitIndex].Roughness;
        float Reflectivity = Boxes[HitIndex].Reflectivity;
        float Refractivity = Boxes[HitIndex].Refractivity;
        float Transparency = Boxes[HitIndex].Transparency;
        bool IsGlass = Transparency > 0.05 || Refractivity > 0.05;

        vec3 GiAccum = vec3(0.0);
        if (!IsGlass) {
            float DistCam = length(HitPos - CameraPos);
            int LocalGi = GiSamples;
            if (DistCam > 80.0) LocalGi = 1;
            else if (DistCam > 40.0) LocalGi = 2;
            else if (BoxCount > 12) LocalGi = max(1, GiSamples - 2);
            for (int S = 0; S < GiSamples; S++) {
                if (S >= LocalGi) break;
                vec3 Seed = HitPos * 13.7 + vec3(float(S) * 91.3, Time * 7.0, Uv.x * 43.0 + Uv.y * 61.0);
                GiAccum += SampleGi(HitPos, PerturbedNormal, HitIndex, SunDir, MoonDir, Seed);
            }
            GiAccum /= float(max(LocalGi, 1));
        }

        float BodyWeight = (1.0 - Reflectivity * mix(0.9, 0.55, Roughness));
        vec3 DiffuseLit = BaseColor * (DirectLight + GiAccum * GiStrength) * BodyWeight;

        vec3 Incident = normalize(HitPos - CameraPos);
        float CosTheta = max(0.0, dot(-Incident, PerturbedNormal));
        vec3 Lit = DiffuseLit;

        if (Reflectivity > 0.001) {
            float F0 = mix(0.04, 0.95, Reflectivity);
            float Fresnel = SchlickFresnel(CosTheta, F0);

            vec3 ReflSeed = HitPos * 19.1 + vec3(Time * 5.3, Uv.x * 71.0, Uv.y * 29.0);
            int ReflSamples = IsGlass ? 1 : ReflectionSamplesMax;
            vec3 ReflColor = SampleReflection(
                HitPos, PerturbedNormal, Incident, HitIndex,
                Roughness, SunDir, MoonDir, ReflSeed, ReflSamples
            );

            vec3 SpecularTint = mix(vec3(1.0), BaseColor, clamp(Reflectivity * 0.4, 0.0, 1.0));
            float ReflectAmount = Reflectivity * mix(Fresnel, 1.0, Reflectivity * 0.5);
            ReflectAmount *= (1.0 - Roughness * 0.4);
            ReflectAmount = clamp(ReflectAmount, 0.0, 1.0);
            Lit += ReflColor * SpecularTint * ReflectAmount * mix(1.0, 0.35, Transparency);
        }

        if (IsGlass) {
            // Simple transmission for mostly-transparent parts (avoids "portal" look
            // on back faces). Full EvalHit only when refractive.
            if (Refractivity > 0.15) {
                Lit = EvalHit(HitIndex, HitPos, PerturbedNormal, RayDir, SunDir, MoonDir, MaxPathDepth, ShadowSeed);
            } else {
                // Continue ray behind the surface; blend with surface shading
                vec3 Nf = PerturbedNormal;
                if (dot(Nf, RayDir) > 0.0) Nf = -Nf;
                float Tt; vec3 Tn;
                int TIdx = TraceScene(HitPos + RayDir * 0.08, RayDir, HitIndex, Tt, Tn);
                vec3 Behind;
                if (TIdx >= 0) {
                    Behind = ShadeDirect(TIdx, HitPos + RayDir * Tt, Tn, SunDir, MoonDir);
                } else {
                    Behind = GetSky(RayDir, SunDir, MoonDir);
                }
                float alpha = clamp(1.0 - Transparency, 0.05, 1.0);
                // Premultiplied-style blend: see through + tinted surface
                Lit = mix(Behind, DiffuseLit / max(BodyWeight, 0.001), alpha * 0.85);
                Lit = mix(Lit, Behind * BaseColor, Transparency * 0.5);
            }
        }

        FinalColor = Lit;

        float FogFactor = 1.0 - exp(-MinT * 0.0018);
        vec3 FogColor = GetAtmosphere(RayDir, SunDir);
        FinalColor = mix(FinalColor, FogColor, FogFactor);

    } else {
        FinalColor = GetSky(RayDir, SunDir, MoonDir);
    }

    if (HighlightEnabled > 0.5 && HitIndex != -1 && Boxes[HitIndex].IsHighlighted > 0.5) {
        FinalColor = mix(FinalColor, HighlightFillColor, clamp(HighlightFillAlpha, 0.0, 0.95));
        // Cheap 4-tap outline (same camera rays as main render Γò¼├┤Γö£ΓûôΓö¼Γò¥╬ô├╢┬ú╬ô├╢├▒Γò¼├┤Γö£ΓòóΓö¼├║╬ô├╢┬úΓö£┬¬Γò¼├┤Γö£ΓòóΓö¼├║╬ô├╢┬úΓö£├ª correct perspective)
        float step = 1.6 / max(Resolution.y, 1.0);
        float edge = 0.0;
        for (int i = 0; i < 4; i++) {
            float a = float(i) * 1.5707963 + 0.785398;
            vec2 oUv = Uv + vec2(cos(a), sin(a)) * step;
            vec3 oDir = normalize(CameraForward + CameraRight * oUv.x * TanFov - CameraUp * oUv.y * TanFov);
            float oT; vec3 oN;
            int oIdx = TraceScene(CameraPos, oDir, -1, oT, oN);
            if (oIdx < 0 || Boxes[oIdx].IsHighlighted < 0.5) { edge = 1.0; break; }
        }
        if (edge > 0.5) {
            FinalColor = mix(FinalColor, HighlightOutlineColor, clamp(HighlightOutlineAlpha, 0.0, 1.0));
        }
    }

    // Editor adornments: separate list, unlit, AlwaysOnTop, same perspective as scene
    if (AdornCount > 0) {
        float At; vec3 An;
        int Ai = TraceAdornments(CameraPos, RayDir, At, An);
        if (Ai >= 0) {
            vec3 ac = AdornBoxes[Ai].Color;
            float a = clamp(1.0 - AdornBoxes[Ai].Transparency, 0.08, 1.0);
            // soft unlit + slight facing term
            float facing = 0.55 + 0.45 * max(0.0, dot(An, -RayDir));
            FinalColor = mix(FinalColor, ac * facing, a);
        }
    }


    vec3 Mapped = FinalColor * 0.85;
    Mapped = Mapped / (Mapped + vec3(0.85));
    Mapped = pow(max(Mapped, vec3(0.0)), vec3(1.0 / 2.2));
    Mapped = clamp(Mapped, 0.0, 1.0);

    Mapped = mix(Mapped, Mapped * Mapped * (3.0 - 2.0 * Mapped), 0.12);

    float Far = max(FarPlane, 1.0);
    float Depth = 1.0;
    if (HitIndex != -1) {
        Depth = clamp(MinT / Far, 0.0, 0.999);
    }

    if (PassIndex > 0) {
        vec4 Prev = Texel(PrevPass, TextureCoords);
        if (Prev.a <= Depth + 1e-5) {
            return Prev;
        }
    }

    return vec4(Mapped, Depth);
}