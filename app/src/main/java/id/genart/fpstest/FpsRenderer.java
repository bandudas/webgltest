package id.genart.fpstest;

import android.opengl.GLES30;
import android.opengl.GLSurfaceView;
import android.util.Log;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.Locale;
import java.util.Random;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/**
 * Renderer uji OpenGL ES 3.0 dengan 3 mode:
 *  0 = shader prosedural (fbm noise) -> menguji beban fragment shader
 *  1 = flow field + jejak, partikel disimulasikan di GPU (transform feedback)
 *  2 = overdraw: blob additive besar bertumpuk -> menguji fill-rate / bandwidth
 *
 * Scene dirender ke framebuffer beresolusi lebih rendah, lalu di-scale ke layar.
 * Mode resolusi AUTO menurunkan/menaikkan resolusi untuk menjaga ~60 fps.
 */
public class FpsRenderer implements GLSurfaceView.Renderer {

    public interface Hud {
        void onHud(String text);
    }

    private static final String TAG = "GenArtFps";

    public static final int MODE_COUNT = 5;
    public static final int[] RES_STEPS = {0, 720, 540, 360}; // 0 = AUTO (tinggi scene dalam piksel)
    private static final String[] MODE_NAMES = {
            "Shader prosedural", "Flow field + jejak", "Overdraw (fill-rate)",
            "3D: objek low-poly", "3D: bola berdeformasi"};
    private static final int[] INSTANCES = {64, 256, 1024, 2048, 4096};
    private static final int INST_SUBDIV = 1; // 80 segitiga per objek
    private static final int[] DEFORM_SUBDIV = {2, 3, 4, 5, 6};
    private static final int[] OCTAVES = {1, 2, 3, 4, 6};
    private static final int[] PARTICLES = {4096, 8192, 16384, 32768, 65536};
    private static final int[] BLOBS = {4, 8, 16, 32, 64};
    private static final int MAX_PARTICLES = 65536;
    private static final int AUTO_MAX_H = 720;
    private static final int AUTO_MIN_H = 288;

    // Diatur dari thread UI, dibaca di thread GL.
    public volatile int mode = 0;
    public volatile int level = 2;     // indeks 0..4 (ditampilkan 1..5)
    public volatile int resMode = 0;   // indeks ke RES_STEPS

    private final Hud hudListener;
    private float refreshRate = 60f;

    // ukuran
    private int viewW = 1, viewH = 1, sceneW = 0, sceneH = 0;
    private int autoH = AUTO_MAX_H;
    private boolean needResize = true;
    private int appliedRes = -1, appliedMode = -1;

    // GL objek
    private int progShader, progFade, progBlit, progUpdate, progDraw, progBlob;
    private int progInst, progDeform;
    private int inVP, inT, inN, inCam, dfVP, dfT, dfCam;
    private Mesh[] meshes = new Mesh[7];
    private final float[] proj = new float[16], view = new float[16], vp = new float[16];

    private static class Mesh {
        int vbo, ibo, indexCount, triCount;
    }
    private int vao;
    private final int[] pbuf = new int[2];
    private int pCur = 0;
    private int trailCur = 0;
    private Target tA, tB;

    // uniform lokasi
    private int shT, shRes, shOct;
    private int fdTex, fdRes;
    private int blTex, blRes;
    private int upT, upDt, upAspect;
    private int drGain, drSize;
    private int bbT, bbAspect;

    // waktu & statistik
    private long lastNs = 0;
    private float time = 0f;
    private int statFrames = 0;
    private float statTime = 0f, shownFps = 0f;
    private float hudTimer = 0f, logTimer = 0f;
    private int adaptFrames = 0;
    private float adaptTime = 0f;
    private int goodWindows = 0, cooldown = 0;
    private long growBlockedUntilNs = 0;
    private String glInfo = "";

    private static class Target {
        int fbo, tex, depth, w, h;
    }

    public FpsRenderer(Hud hud) {
        this.hudListener = hud;
    }

    public void setRefreshRate(float hz) {
        if (hz > 20f && hz < 245f) refreshRate = hz;
    }

    // ------------------------------------------------------------------ shaders

    private static final String V_TRI =
            "#version 300 es\n" +
            "void main(){\n" +
            "  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));\n" +
            "  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);\n" +
            "}\n";

    private static final String F_SHADER =
            "#version 300 es\n" +
            "precision highp float;\n" +
            "uniform float uT; uniform vec2 uRes; uniform int uOct;\n" +
            "out vec4 o;\n" +
            "float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }\n" +
            "float n(vec2 p){\n" +
            "  vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);\n" +
            "  float a = h(i), b = h(i + vec2(1.0, 0.0)), c = h(i + vec2(0.0, 1.0)), d = h(i + vec2(1.0, 1.0));\n" +
            "  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);\n" +
            "}\n" +
            "float fbm(vec2 p){\n" +
            "  float v = 0.0, a = 0.5;\n" +
            "  for (int i = 0; i < 6; i++) {\n" +
            "    if (i >= uOct) break;\n" +
            "    v += a * n(p); p = p * 2.0 + vec2(1.7, 9.2); a *= 0.5;\n" +
            "  }\n" +
            "  return v;\n" +
            "}\n" +
            "void main(){\n" +
            "  vec2 uv = gl_FragCoord.xy / uRes;\n" +
            "  vec2 p = (uv - 0.5) * vec2(uRes.x / uRes.y, 1.0) * 3.0;\n" +
            "  float q = fbm(p + vec2(uT * 0.10, 0.0));\n" +
            "  float r = fbm(p + q * 2.0 + vec2(uT * 0.06, -uT * 0.04));\n" +
            "  vec3 col = 0.5 + 0.5 * cos(6.2831 * (r * 1.2 + vec3(0.0, 0.33, 0.67)) + uT * 0.15);\n" +
            "  col *= 0.35 + 0.9 * q;\n" +
            "  o = vec4(col, 1.0);\n" +
            "}\n";

    private static final String F_FADE =
            "#version 300 es\n" +
            "precision mediump float;\n" +
            "uniform sampler2D uTex; uniform vec2 uRes;\n" +
            "out vec4 o;\n" +
            "void main(){\n" +
            "  vec3 c = texture(uTex, gl_FragCoord.xy / uRes).rgb;\n" +
            "  o = vec4(max(c * 0.955 - 0.002, 0.0), 1.0);\n" +
            "}\n";

    private static final String F_BLIT =
            "#version 300 es\n" +
            "precision mediump float;\n" +
            "uniform sampler2D uTex; uniform vec2 uRes;\n" +
            "out vec4 o;\n" +
            "void main(){ o = vec4(texture(uTex, gl_FragCoord.xy / uRes).rgb, 1.0); }\n";

    // Update partikel (transform feedback). State: x, y, umur.
    private static final String V_UPDATE =
            "#version 300 es\n" +
            "precision highp float;\n" +
            "layout(location = 0) in vec3 aS;\n" +
            "out vec3 vS;\n" +
            "uniform float uT; uniform float uDt; uniform float uAspect;\n" +
            "float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }\n" +
            "vec2 field(vec2 p, float t){\n" +
            "  p *= vec2(uAspect, 1.0) * 1.8;\n" +
            "  float a = 3.0 * sin(p.x * 1.3 + t * 0.21 + sin(p.y * 1.7 - t * 0.13))\n" +
            "          + 3.0 * cos(p.y * 1.1 - t * 0.17 + sin(p.x * 1.9 + t * 0.11));\n" +
            "  return vec2(cos(a), sin(a));\n" +
            "}\n" +
            "void main(){\n" +
            "  vec2 p = aS.xy; float age = aS.z;\n" +
            "  p += field(p, uT) * 0.30 * uDt;\n" +
            "  age += uDt * 0.20;\n" +
            "  if (age > 1.0 || abs(p.x) > 1.05 || abs(p.y) > 1.05) {\n" +
            "    vec2 s = vec2(float(gl_VertexID) * 0.0137, uT);\n" +
            "    p = vec2(hash(s), hash(s + vec2(7.7, 3.1))) * 2.0 - 1.0;\n" +
            "    age = hash(s + vec2(1.3, 9.9)) * 0.2;\n" +
            "  }\n" +
            "  vS = vec3(p, age);\n" +
            "  gl_Position = vec4(p, 0.0, 1.0);\n" +
            "}\n";

    private static final String F_NOP =
            "#version 300 es\n" +
            "precision lowp float;\n" +
            "out vec4 o;\n" +
            "void main(){ o = vec4(0.0); }\n";

    private static final String V_DRAW =
            "#version 300 es\n" +
            "precision highp float;\n" +
            "layout(location = 0) in vec3 aS;\n" +
            "uniform float uSize; uniform float uGain;\n" +
            "out vec3 vC;\n" +
            "void main(){\n" +
            "  gl_Position = vec4(aS.xy, 0.0, 1.0);\n" +
            "  gl_PointSize = uSize;\n" +
            "  vec3 c = 0.5 + 0.5 * cos(6.2831 * (aS.x * 0.25 + aS.y * 0.20 + vec3(0.0, 0.33, 0.67)));\n" +
            "  vC = c * sin(3.14159 * clamp(aS.z, 0.0, 1.0)) * uGain;\n" +
            "}\n";

    private static final String F_DRAW =
            "#version 300 es\n" +
            "precision mediump float;\n" +
            "in vec3 vC;\n" +
            "out vec4 o;\n" +
            "void main(){ o = vec4(vC, 1.0); }\n";

    private static final String V_BLOB =
            "#version 300 es\n" +
            "precision highp float;\n" +
            "uniform float uT; uniform float uAspect;\n" +
            "out vec2 vP; out float vI;\n" +
            "void main(){\n" +
            "  float id = float(gl_InstanceID);\n" +
            "  vec2 c = vec2(sin(uT * 0.30 + id * 1.7), cos(uT * 0.23 + id * 2.3)) * 0.6;\n" +
            "  float r = 0.55 + 0.20 * sin(id + uT * 0.5);\n" +
            "  vec2 q = vec2(float(gl_VertexID & 1), float(gl_VertexID >> 1)) * 2.0 - 1.0;\n" +
            "  vP = q; vI = id;\n" +
            "  gl_Position = vec4(c + q * vec2(r / uAspect, r), 0.0, 1.0);\n" +
            "}\n";

    private static final String F_BLOB =
            "#version 300 es\n" +
            "precision mediump float;\n" +
            "in vec2 vP; in float vI;\n" +
            "out vec4 o;\n" +
            "void main(){\n" +
            "  float a = exp(-3.0 * dot(vP, vP));\n" +
            "  vec3 col = 0.5 + 0.5 * cos(6.2831 * (vI * 0.13 + vec3(0.0, 0.33, 0.67)));\n" +
            "  o = vec4(col * a * 0.22, 1.0);\n" +
            "}\n";

    // ---- 3D: banyak objek (icosphere 80 segitiga) yang berputar membentuk spiral.
    private static final String V_INST =
            "#version 300 es\n" +
            "precision highp float;\n" +
            "layout(location = 0) in vec3 aPos;\n" +
            "uniform mat4 uVP; uniform float uT; uniform float uN;\n" +
            "out vec3 vW; out float vC;\n" +
            "vec3 rotA(vec3 p, vec3 k, float a){\n" +
            "  float c = cos(a), s = sin(a);\n" +
            "  return p * c + cross(k, p) * s + k * dot(k, p) * (1.0 - c);\n" +
            "}\n" +
            "void main(){\n" +
            "  float id = float(gl_InstanceID);\n" +
            "  float k = (id + 0.5) / uN;\n" +
            "  float ang = id * 2.39996 + uT * 0.25 * (1.0 + k);\n" +
            "  float r = 1.6 + 1.1 * sin(k * 12.566 + uT * 0.5);\n" +
            "  float y = (k * 2.0 - 1.0) * 2.4 + 0.3 * sin(uT + id * 0.1);\n" +
            "  vec3 c = vec3(cos(ang) * r, y, sin(ang) * r);\n" +
            "  float s = 0.9 / pow(uN, 0.3333);\n" +
            "  vec3 axis = normalize(vec3(sin(id * 1.7), cos(id * 1.3), 0.6));\n" +
            "  vec3 p = rotA(aPos, axis, uT * (0.5 + fract(id * 0.618))) * s * vec3(1.0, 1.0, 1.6) + c;\n" +
            "  vW = p; vC = k + uT * 0.02;\n" +
            "  gl_Position = uVP * vec4(p, 1.0);\n" +
            "}\n";

    // ---- 3D: satu bola icosphere yang dideformasi gelombang di vertex shader.
    private static final String V_DEFORM =
            "#version 300 es\n" +
            "precision highp float;\n" +
            "layout(location = 0) in vec3 aPos;\n" +
            "uniform mat4 uVP; uniform float uT;\n" +
            "out vec3 vW; out float vC;\n" +
            "float wave(vec3 p){\n" +
            "  return sin(p.x * 3.1 + uT) * sin(p.y * 2.7 - uT * 0.8) * sin(p.z * 3.3 + uT * 0.6)\n" +
            "       + 0.5 * sin(p.x * 7.0 + p.y * 5.0 - uT * 1.3) * sin(p.z * 6.0 + uT);\n" +
            "}\n" +
            "void main(){\n" +
            "  vec3 n = normalize(aPos);\n" +
            "  float d = wave(n);\n" +
            "  vec3 p = n * (1.6 + 0.45 * d);\n" +
            "  vW = p; vC = 0.5 * d + uT * 0.03;\n" +
            "  gl_Position = uVP * vec4(p, 1.0);\n" +
            "}\n";

    // Flat shading dari turunan layar (tanpa atribut normal), diffuse + rim + kabut.
    private static final String F_LIT =
            "#version 300 es\n" +
            "precision highp float;\n" +
            "in vec3 vW; in float vC;\n" +
            "uniform vec3 uCam;\n" +
            "out vec4 o;\n" +
            "void main(){\n" +
            "  vec3 n = normalize(cross(dFdx(vW), dFdy(vW)));\n" +
            "  vec3 V = normalize(uCam - vW);\n" +
            "  if (dot(n, V) < 0.0) n = -n;\n" +
            "  vec3 L = normalize(vec3(0.5, 0.8, 0.3));\n" +
            "  float d = max(dot(n, L), 0.0);\n" +
            "  float rim = pow(1.0 - max(dot(n, V), 0.0), 3.0);\n" +
            "  vec3 base = 0.5 + 0.5 * cos(6.2831 * (vC + vec3(0.0, 0.33, 0.67)));\n" +
            "  vec3 col = base * (0.12 + 0.88 * d) + rim * 0.35;\n" +
            "  float fog = clamp(1.6 * exp(-0.12 * length(uCam - vW)), 0.0, 1.0);\n" +
            "  o = vec4(col * fog, 1.0);\n" +
            "}\n";

    // ------------------------------------------------------------------ mesh

    /** Icosphere: subdiv 0 = 20 segitiga, tiap level x4. Indeks ushort (maks subdiv 6 = 40962 verteks). */
    private static Mesh buildIcosphere(int subdiv) {
        float t = (float) ((1.0 + Math.sqrt(5.0)) / 2.0);
        float[] base = {
                -1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, 0,
                0, -1, t, 0, 1, t, 0, -1, -t, 0, 1, -t,
                t, 0, -1, t, 0, 1, -t, 0, -1, -t, 0, 1};
        int[] f = {
                0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
                1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
                3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
                4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1};
        int maxV = 10 * (1 << (2 * subdiv)) + 2;
        float[] v = new float[maxV * 3];
        int vc = 0;
        for (int i = 0; i < 12; i++) {
            float x = base[i * 3], y = base[i * 3 + 1], z = base[i * 3 + 2];
            float l = (float) Math.sqrt(x * x + y * y + z * z);
            v[vc * 3] = x / l;
            v[vc * 3 + 1] = y / l;
            v[vc * 3 + 2] = z / l;
            vc++;
        }
        for (int s = 0; s < subdiv; s++) {
            java.util.HashMap<Long, Integer> mid = new java.util.HashMap<>();
            int[] nf = new int[f.length * 4];
            int k = 0;
            for (int i = 0; i < f.length; i += 3) {
                int a = f[i], b = f[i + 1], c = f[i + 2];
                int ab = 0, bc = 0, ca = 0;
                int[][] pairs = {{a, b}, {b, c}, {c, a}};
                int[] res = new int[3];
                for (int p = 0; p < 3; p++) {
                    int p0 = Math.min(pairs[p][0], pairs[p][1]);
                    int p1 = Math.max(pairs[p][0], pairs[p][1]);
                    long key = ((long) p0 << 32) | p1;
                    Integer idx = mid.get(key);
                    if (idx == null) {
                        float x = v[p0 * 3] + v[p1 * 3];
                        float y = v[p0 * 3 + 1] + v[p1 * 3 + 1];
                        float z = v[p0 * 3 + 2] + v[p1 * 3 + 2];
                        float l = (float) Math.sqrt(x * x + y * y + z * z);
                        v[vc * 3] = x / l;
                        v[vc * 3 + 1] = y / l;
                        v[vc * 3 + 2] = z / l;
                        idx = vc++;
                        mid.put(key, idx);
                    }
                    res[p] = idx;
                }
                ab = res[0];
                bc = res[1];
                ca = res[2];
                nf[k++] = a; nf[k++] = ab; nf[k++] = ca;
                nf[k++] = b; nf[k++] = bc; nf[k++] = ab;
                nf[k++] = c; nf[k++] = ca; nf[k++] = bc;
                nf[k++] = ab; nf[k++] = bc; nf[k++] = ca;
            }
            f = nf;
        }

        FloatBuffer vb = ByteBuffer.allocateDirect(vc * 3 * 4)
                .order(ByteOrder.nativeOrder()).asFloatBuffer();
        vb.put(v, 0, vc * 3).position(0);
        java.nio.ShortBuffer ib = ByteBuffer.allocateDirect(f.length * 2)
                .order(ByteOrder.nativeOrder()).asShortBuffer();
        for (int x : f) ib.put((short) x);
        ib.position(0);

        Mesh m = new Mesh();
        int[] id = new int[2];
        GLES30.glGenBuffers(2, id, 0);
        m.vbo = id[0];
        m.ibo = id[1];
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, m.vbo);
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, vc * 3 * 4, vb, GLES30.GL_STATIC_DRAW);
        GLES30.glBindBuffer(GLES30.GL_ELEMENT_ARRAY_BUFFER, m.ibo);
        GLES30.glBufferData(GLES30.GL_ELEMENT_ARRAY_BUFFER, f.length * 2, ib, GLES30.GL_STATIC_DRAW);
        m.indexCount = f.length;
        m.triCount = f.length / 3;
        return m;
    }

    private Mesh mesh(int subdiv) {
        if (meshes[subdiv] == null) meshes[subdiv] = buildIcosphere(subdiv);
        return meshes[subdiv];
    }

    private void bindMesh(Mesh m) {
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, m.vbo);
        GLES30.glEnableVertexAttribArray(0);
        GLES30.glVertexAttribPointer(0, 3, GLES30.GL_FLOAT, false, 12, 0);
        GLES30.glBindBuffer(GLES30.GL_ELEMENT_ARRAY_BUFFER, m.ibo);
    }

    private void setCamera(float dist, float[] eyeOut) {
        float a = time * 0.12f;
        float ex = (float) Math.sin(a) * dist;
        float ey = 1.2f + (float) Math.sin(time * 0.07f) * 1.5f;
        float ez = (float) Math.cos(a) * dist;
        android.opengl.Matrix.perspectiveM(proj, 0, 50f, (float) sceneW / sceneH, 0.1f, 50f);
        android.opengl.Matrix.setLookAtM(view, 0, ex, ey, ez, 0f, 0f, 0f, 0f, 1f, 0f);
        android.opengl.Matrix.multiplyMM(vp, 0, proj, 0, view, 0);
        eyeOut[0] = ex;
        eyeOut[1] = ey;
        eyeOut[2] = ez;
    }

    private final float[] eye = new float[3];

    private void begin3D(Target t) {
        bindTarget(t);
        GLES30.glClearColor(0.01f, 0.01f, 0.02f, 1f);
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT | GLES30.GL_DEPTH_BUFFER_BIT);
        GLES30.glEnable(GLES30.GL_DEPTH_TEST);
        GLES30.glDepthFunc(GLES30.GL_LESS);
        GLES30.glDisable(GLES30.GL_BLEND);
    }

    private void end3D() {
        GLES30.glDisable(GLES30.GL_DEPTH_TEST);
        GLES30.glBindBuffer(GLES30.GL_ELEMENT_ARRAY_BUFFER, 0);
    }

    private String levelDesc(int md, int lv) {
        switch (md) {
            case 0: return OCTAVES[lv] + " oktaf noise";
            case 1: return PARTICLES[lv] + " partikel";
            case 2: return BLOBS[lv] + " lapis blob";
            case 3: return INSTANCES[lv] + " objek = "
                    + (INSTANCES[lv] * (20 << (2 * INST_SUBDIV))) + " segitiga";
            default: return "subdiv " + DEFORM_SUBDIV[lv] + " = "
                    + (20 << (2 * DEFORM_SUBDIV[lv])) + " segitiga";
        }
    }

    // ------------------------------------------------------------------ util GL

    private static int compile(int type, String src) {
        int s = GLES30.glCreateShader(type);
        GLES30.glShaderSource(s, src);
        GLES30.glCompileShader(s);
        int[] ok = new int[1];
        GLES30.glGetShaderiv(s, GLES30.GL_COMPILE_STATUS, ok, 0);
        if (ok[0] == 0) {
            String log = GLES30.glGetShaderInfoLog(s);
            GLES30.glDeleteShader(s);
            throw new RuntimeException("Shader gagal dikompilasi: " + log + "\n" + src);
        }
        return s;
    }

    private static int link(String vs, String fs, String[] tfVaryings) {
        int v = compile(GLES30.GL_VERTEX_SHADER, vs);
        int f = compile(GLES30.GL_FRAGMENT_SHADER, fs);
        int p = GLES30.glCreateProgram();
        GLES30.glAttachShader(p, v);
        GLES30.glAttachShader(p, f);
        if (tfVaryings != null) {
            GLES30.glTransformFeedbackVaryings(p, tfVaryings, GLES30.GL_INTERLEAVED_ATTRIBS);
        }
        GLES30.glLinkProgram(p);
        int[] ok = new int[1];
        GLES30.glGetProgramiv(p, GLES30.GL_LINK_STATUS, ok, 0);
        if (ok[0] == 0) {
            String log = GLES30.glGetProgramInfoLog(p);
            throw new RuntimeException("Program gagal di-link: " + log);
        }
        GLES30.glDeleteShader(v);
        GLES30.glDeleteShader(f);
        return p;
    }

    private static int loc(int prog, String name) {
        return GLES30.glGetUniformLocation(prog, name);
    }

    private Target createTarget(int w, int h) {
        Target t = new Target();
        t.w = w;
        t.h = h;
        int[] id = new int[1];
        GLES30.glGenTextures(1, id, 0);
        t.tex = id[0];
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, t.tex);
        GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA, w, h, 0,
                GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, null);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE);
        GLES30.glGenFramebuffers(1, id, 0);
        t.fbo = id[0];
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, t.fbo);
        GLES30.glFramebufferTexture2D(GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0,
                GLES30.GL_TEXTURE_2D, t.tex, 0);
        GLES30.glGenRenderbuffers(1, id, 0);
        t.depth = id[0];
        GLES30.glBindRenderbuffer(GLES30.GL_RENDERBUFFER, t.depth);
        GLES30.glRenderbufferStorage(GLES30.GL_RENDERBUFFER, GLES30.GL_DEPTH_COMPONENT16, w, h);
        GLES30.glFramebufferRenderbuffer(GLES30.GL_FRAMEBUFFER, GLES30.GL_DEPTH_ATTACHMENT,
                GLES30.GL_RENDERBUFFER, t.depth);
        int st = GLES30.glCheckFramebufferStatus(GLES30.GL_FRAMEBUFFER);
        if (st != GLES30.GL_FRAMEBUFFER_COMPLETE) {
            throw new RuntimeException("Framebuffer tidak lengkap: 0x" + Integer.toHexString(st));
        }
        GLES30.glClearColor(0f, 0f, 0f, 1f);
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT);
        return t;
    }

    private void clearTarget(Target t) {
        if (t == null) return;
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, t.fbo);
        GLES30.glClearColor(0f, 0f, 0f, 1f);
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT);
    }

    private void deleteTarget(Target t) {
        if (t == null) return;
        GLES30.glDeleteFramebuffers(1, new int[]{t.fbo}, 0);
        GLES30.glDeleteTextures(1, new int[]{t.tex}, 0);
        GLES30.glDeleteRenderbuffers(1, new int[]{t.depth}, 0);
    }

    private void bindTarget(Target t) {
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, t.fbo);
        GLES30.glViewport(0, 0, t.w, t.h);
    }

    private void drawTri() {
        GLES30.glDrawArrays(GLES30.GL_TRIANGLES, 0, 3);
    }

    // ------------------------------------------------------------------ lifecycle

    @Override
    public void onSurfaceCreated(GL10 unused, EGLConfig config) {
        glInfo = GLES30.glGetString(GLES30.GL_RENDERER) + " | " + GLES30.glGetString(GLES30.GL_VERSION);
        Log.i(TAG, "GL: " + glInfo);

        progShader = link(V_TRI, F_SHADER, null);
        progFade = link(V_TRI, F_FADE, null);
        progBlit = link(V_TRI, F_BLIT, null);
        progUpdate = link(V_UPDATE, F_NOP, new String[]{"vS"});
        progDraw = link(V_DRAW, F_DRAW, null);
        progBlob = link(V_BLOB, F_BLOB, null);
        progInst = link(V_INST, F_LIT, null);
        progDeform = link(V_DEFORM, F_LIT, null);
        inVP = loc(progInst, "uVP");
        inT = loc(progInst, "uT");
        inN = loc(progInst, "uN");
        inCam = loc(progInst, "uCam");
        dfVP = loc(progDeform, "uVP");
        dfT = loc(progDeform, "uT");
        dfCam = loc(progDeform, "uCam");
        meshes = new Mesh[7]; // konteks baru -> buffer lama tidak valid

        shT = loc(progShader, "uT");
        shRes = loc(progShader, "uRes");
        shOct = loc(progShader, "uOct");
        fdTex = loc(progFade, "uTex");
        fdRes = loc(progFade, "uRes");
        blTex = loc(progBlit, "uTex");
        blRes = loc(progBlit, "uRes");
        upT = loc(progUpdate, "uT");
        upDt = loc(progUpdate, "uDt");
        upAspect = loc(progUpdate, "uAspect");
        drGain = loc(progDraw, "uGain");
        drSize = loc(progDraw, "uSize");
        bbT = loc(progBlob, "uT");
        bbAspect = loc(progBlob, "uAspect");

        int[] id = new int[1];
        GLES30.glGenVertexArrays(1, id, 0);
        vao = id[0];
        GLES30.glBindVertexArray(vao);

        Random rnd = new Random(1234);
        FloatBuffer fb = ByteBuffer.allocateDirect(MAX_PARTICLES * 3 * 4)
                .order(ByteOrder.nativeOrder()).asFloatBuffer();
        for (int i = 0; i < MAX_PARTICLES; i++) {
            fb.put(rnd.nextFloat() * 2f - 1f);
            fb.put(rnd.nextFloat() * 2f - 1f);
            fb.put(rnd.nextFloat());
        }
        GLES30.glGenBuffers(2, pbuf, 0);
        for (int i = 0; i < 2; i++) {
            fb.position(0);
            GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, pbuf[i]);
            GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, MAX_PARTICLES * 3 * 4, fb, GLES30.GL_DYNAMIC_COPY);
        }
        pCur = 0;
        trailCur = 0;

        // Konteks baru -> target lama sudah tidak valid.
        tA = null;
        tB = null;
        sceneW = 0;
        sceneH = 0;
        needResize = true;
        appliedRes = -1;
        appliedMode = -1;
        lastNs = 0;
    }

    @Override
    public void onSurfaceChanged(GL10 unused, int w, int h) {
        viewW = Math.max(1, w);
        viewH = Math.max(1, h);
        autoH = Math.min(AUTO_MAX_H, viewH);
        needResize = true;
    }

    private int desiredHeight() {
        int rm = resMode;
        int h = (rm == 0) ? autoH : RES_STEPS[rm];
        return Math.max(AUTO_MIN_H > viewH ? viewH : AUTO_MIN_H, Math.min(h, viewH));
    }

    private void applyResize() {
        int h = desiredHeight();
        int w = ((int) (h * (float) viewW / viewH)) & ~1;
        if (w < 2) w = 2;
        if (tA == null || tB == null || w != sceneW || h != sceneH) {
            deleteTarget(tA);
            deleteTarget(tB);
            tA = createTarget(w, h);
            tB = createTarget(w, h);
            sceneW = w;
            sceneH = h;
            trailCur = 0;
        }
        needResize = false;
    }

    // ------------------------------------------------------------------ adaptif

    private void adapt(float dt, long nowNs) {
        adaptFrames++;
        adaptTime += dt;
        if (adaptFrames < 30) return;
        float fps = adaptFrames / adaptTime;
        adaptFrames = 0;
        adaptTime = 0f;
        if (cooldown > 0) cooldown -= 30;
        if (resMode != 0) {
            goodWindows = 0;
            return;
        }
        int maxH = Math.min(AUTO_MAX_H, viewH);
        if (fps < refreshRate * 0.93f && cooldown <= 0 && autoH > AUTO_MIN_H) {
            autoH = Math.max(AUTO_MIN_H, (int) (autoH * 0.85f));
            growBlockedUntilNs = nowNs + 10_000_000_000L;
            cooldown = 60;
            goodWindows = 0;
            needResize = true;
        } else if (fps >= refreshRate * 0.98f) {
            goodWindows++;
            if (goodWindows >= 3 && cooldown <= 0 && autoH < maxH && nowNs > growBlockedUntilNs) {
                autoH = Math.min(maxH, (int) (autoH * 1.1f) + 2);
                goodWindows = 0;
                cooldown = 60;
                needResize = true;
            }
        } else {
            goodWindows = 0;
        }
    }

    // ------------------------------------------------------------------ gambar

    @Override
    public void onDrawFrame(GL10 unused) {
        long now = System.nanoTime();
        float dt = (lastNs == 0) ? 1f / 60f : (now - lastNs) / 1e9f;
        lastNs = now;
        float simDt = Math.min(dt, 0.05f);
        time += simDt;

        if (resMode == 0) adapt(Math.min(dt, 0.5f), now);

        int md = mode;
        int rm = resMode;
        int lv = level;
        if (rm != appliedRes) {
            appliedRes = rm;
            needResize = true;
        }
        if (needResize || tA == null) applyResize();
        if (md != appliedMode) {
            appliedMode = md;
            clearTarget(tA);
            clearTarget(tB);
            trailCur = 0;
        }

        Target latest;
        GLES30.glBindVertexArray(vao);

        if (md == 0) {
            bindTarget(tA);
            GLES30.glDisable(GLES30.GL_BLEND);
            GLES30.glUseProgram(progShader);
            GLES30.glUniform1f(shT, time);
            GLES30.glUniform2f(shRes, sceneW, sceneH);
            GLES30.glUniform1i(shOct, OCTAVES[lv]);
            drawTri();
            latest = tA;
        } else if (md == 1) {
            int n = PARTICLES[lv];
            stepParticles(n, simDt);

            Target src = (trailCur == 0) ? tA : tB;
            Target dst = (trailCur == 0) ? tB : tA;

            bindTarget(dst);
            GLES30.glDisable(GLES30.GL_BLEND);
            GLES30.glUseProgram(progFade);
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0);
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, src.tex);
            GLES30.glUniform1i(fdTex, 0);
            GLES30.glUniform2f(fdRes, sceneW, sceneH);
            drawTri();

            GLES30.glEnable(GLES30.GL_BLEND);
            GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE);
            GLES30.glUseProgram(progDraw);
            GLES30.glUniform1f(drSize, Math.max(1f, sceneH / 360f));
            GLES30.glUniform1f(drGain, Math.min(0.5f, 0.2f * 16384f / n));
            GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, pbuf[pCur]);
            GLES30.glEnableVertexAttribArray(0);
            GLES30.glVertexAttribPointer(0, 3, GLES30.GL_FLOAT, false, 12, 0);
            GLES30.glDrawArrays(GLES30.GL_POINTS, 0, n);
            GLES30.glDisable(GLES30.GL_BLEND);

            trailCur = 1 - trailCur;
            latest = dst;
        } else if (md == 3) {
            Mesh m = mesh(INST_SUBDIV);
            begin3D(tA);
            setCamera(7.5f, eye);
            GLES30.glUseProgram(progInst);
            GLES30.glUniformMatrix4fv(inVP, 1, false, vp, 0);
            GLES30.glUniform1f(inT, time);
            GLES30.glUniform1f(inN, INSTANCES[lv]);
            GLES30.glUniform3f(inCam, eye[0], eye[1], eye[2]);
            bindMesh(m);
            GLES30.glDrawElementsInstanced(GLES30.GL_TRIANGLES, m.indexCount,
                    GLES30.GL_UNSIGNED_SHORT, 0, INSTANCES[lv]);
            end3D();
            latest = tA;
        } else if (md == 4) {
            Mesh m = mesh(DEFORM_SUBDIV[lv]);
            begin3D(tA);
            setCamera(5.0f, eye);
            GLES30.glUseProgram(progDeform);
            GLES30.glUniformMatrix4fv(dfVP, 1, false, vp, 0);
            GLES30.glUniform1f(dfT, time);
            GLES30.glUniform3f(dfCam, eye[0], eye[1], eye[2]);
            bindMesh(m);
            GLES30.glDrawElements(GLES30.GL_TRIANGLES, m.indexCount, GLES30.GL_UNSIGNED_SHORT, 0);
            end3D();
            latest = tA;
        } else {
            bindTarget(tA);
            GLES30.glClearColor(0f, 0f, 0f, 1f);
            GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT);
            GLES30.glEnable(GLES30.GL_BLEND);
            GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE);
            GLES30.glUseProgram(progBlob);
            GLES30.glUniform1f(bbT, time);
            GLES30.glUniform1f(bbAspect, (float) sceneW / sceneH);
            GLES30.glDrawArraysInstanced(GLES30.GL_TRIANGLE_STRIP, 0, 4, BLOBS[lv]);
            GLES30.glDisable(GLES30.GL_BLEND);
            latest = tA;
        }

        // Scale ke layar
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0);
        GLES30.glViewport(0, 0, viewW, viewH);
        GLES30.glDisable(GLES30.GL_BLEND);
        GLES30.glUseProgram(progBlit);
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0);
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, latest.tex);
        GLES30.glUniform1i(blTex, 0);
        GLES30.glUniform2f(blRes, viewW, viewH);
        drawTri();

        updateStats(dt, md, lv, rm);
    }

    private void stepParticles(int n, float dt) {
        int src = pbuf[pCur];
        int dst = pbuf[1 - pCur];
        GLES30.glUseProgram(progUpdate);
        GLES30.glUniform1f(upT, time % 97f);
        GLES30.glUniform1f(upDt, dt);
        GLES30.glUniform1f(upAspect, (float) viewW / viewH);

        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, src);
        GLES30.glEnableVertexAttribArray(0);
        GLES30.glVertexAttribPointer(0, 3, GLES30.GL_FLOAT, false, 12, 0);
        GLES30.glBindBufferBase(GLES30.GL_TRANSFORM_FEEDBACK_BUFFER, 0, dst);

        GLES30.glEnable(GLES30.GL_RASTERIZER_DISCARD);
        GLES30.glBeginTransformFeedback(GLES30.GL_POINTS);
        GLES30.glDrawArrays(GLES30.GL_POINTS, 0, n);
        GLES30.glEndTransformFeedback();
        GLES30.glDisable(GLES30.GL_RASTERIZER_DISCARD);

        GLES30.glBindBufferBase(GLES30.GL_TRANSFORM_FEEDBACK_BUFFER, 0, 0);
        pCur = 1 - pCur;
    }

    // ------------------------------------------------------------------ HUD

    private void updateStats(float dt, int md, int lv, int rm) {
        statFrames++;
        statTime += dt;
        hudTimer += dt;
        logTimer += dt;
        if (statTime >= 0.5f) {
            shownFps = statFrames / statTime;
            statFrames = 0;
            statTime = 0f;
        }
        if (hudTimer >= 0.5f) {
            hudTimer = 0f;
            String resName = (rm == 0) ? "AUTO" : (RES_STEPS[rm] + "p");
            String text = String.format(Locale.US,
                    "%s | level %d/5 (%s)\n" +
                    "scene %dx%d -> layar %dx%d [%s]\n" +
                    "FPS %.1f (layar %.0f Hz)\n" +
                    "KIRI/KANAN=mode  ATAS/BAWAH=level  OK=resolusi  MENU=sembunyikan HUD\n" +
                    "%s",
                    MODE_NAMES[md], lv + 1, levelDesc(md, lv), sceneW, sceneH, viewW, viewH, resName,
                    shownFps, refreshRate, glInfo);
            if (hudListener != null) hudListener.onHud(text);
        }
        if (logTimer >= 2f) {
            logTimer = 0f;
            Log.i(TAG, String.format(Locale.US,
                    "mode=%d level=%d scene=%dx%d res=%d fps=%.1f",
                    md, lv + 1, sceneW, sceneH, rm, shownFps));
        }
    }
}
