package id.genart.fpstest;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.opengl.GLSurfaceView;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Display;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;

public class MainActivity extends Activity implements FpsRenderer.Hud {

    private GLSurfaceView glView;
    private TextView hud;
    private FpsRenderer renderer;
    private boolean hudVisible = true;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        renderer = new FpsRenderer(this);
        Display d = getWindowManager().getDefaultDisplay();
        renderer.setRefreshRate(d.getRefreshRate());

        glView = new GLSurfaceView(this);
        glView.setEGLContextClientVersion(3);
        glView.setEGLConfigChooser(8, 8, 8, 8, 0, 0);
        glView.setPreserveEGLContextOnPause(false);
        glView.setRenderer(renderer);
        glView.setRenderMode(GLSurfaceView.RENDERMODE_CONTINUOUSLY);

        hud = new TextView(this);
        hud.setTextColor(Color.WHITE);
        hud.setTypeface(Typeface.MONOSPACE);
        hud.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        hud.setBackgroundColor(0x99000000);
        hud.setPadding(16, 8, 16, 8);
        hud.setText("memulai...");

        FrameLayout root = new FrameLayout(this);
        root.addView(glView, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP | Gravity.START);
        root.addView(hud, lp);
        setContentView(root);
    }

    @Override
    public void onHud(final String text) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                hud.setText(text);
            }
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        glView.onResume();
    }

    @Override
    protected void onPause() {
        glView.onPause();
        super.onPause();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            getWindow().getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        }
    }

    private void nextMode(int delta) {
        renderer.mode = (renderer.mode + delta + FpsRenderer.MODE_COUNT) % FpsRenderer.MODE_COUNT;
    }

    private void changeLevel(int delta) {
        int l = renderer.level + delta;
        if (l < 0) l = 0;
        if (l > 4) l = 4;
        renderer.level = l;
    }

    private void cycleRes() {
        renderer.resMode = (renderer.resMode + 1) % FpsRenderer.RES_STEPS.length;
    }

    private void toggleHud() {
        hudVisible = !hudVisible;
        hud.setVisibility(hudVisible ? View.VISIBLE : View.INVISIBLE);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                nextMode(1);
                return true;
            case KeyEvent.KEYCODE_DPAD_LEFT:
                nextMode(-1);
                return true;
            case KeyEvent.KEYCODE_DPAD_UP:
                changeLevel(1);
                return true;
            case KeyEvent.KEYCODE_DPAD_DOWN:
                changeLevel(-1);
                return true;
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER:
            case KeyEvent.KEYCODE_BUTTON_A:
                cycleRes();
                return true;
            case KeyEvent.KEYCODE_MENU:
            case KeyEvent.KEYCODE_INFO:
            case KeyEvent.KEYCODE_H:
                toggleHud();
                return true;
            default:
                return super.onKeyDown(keyCode, event);
        }
    }

    // Untuk layar sentuh / air mouse: sepertiga kiri/kanan = ganti mode,
    // pita atas/bawah = naik/turun level, sisanya = ganti resolusi.
    @Override
    public boolean onTouchEvent(MotionEvent e) {
        if (e.getAction() == MotionEvent.ACTION_UP) {
            float w = glView.getWidth();
            float h = glView.getHeight();
            float x = e.getX();
            float y = e.getY();
            if (y < h * 0.2f) {
                changeLevel(1);
            } else if (y > h * 0.8f) {
                changeLevel(-1);
            } else if (x < w / 3f) {
                nextMode(-1);
            } else if (x > w * 2f / 3f) {
                nextMode(1);
            } else {
                cycleRes();
            }
        }
        return true;
    }
}
