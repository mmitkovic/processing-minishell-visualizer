// ---------- customize these ----------
String USER = "mmitkovi";
String PAIR = "tafanasi";
String HOST = "42-warsaw";
String HOME_PATH = "/home/" + USER + "/42/minishell";
// -------------------------------------

class Step {
  String prompt; String cmd; String[] out;
  Step(String prompt, String cmd, String... out) { this.prompt=prompt; this.cmd=cmd; this.out=out; }
}

class Theme {
  int bg, prompt, output, error, banner, footer, cursor;
  Theme(int bg, int prompt, int output, int error, int banner, int footer, int cursor){
    this.bg=bg; this.prompt=prompt; this.output=output; this.error=error;
    this.banner=banner; this.footer=footer; this.cursor=cursor;
  }
}

// ---- themes (cycle order) ----
//            bg        prompt    output    error     banner    footer    cursor
Theme[] THEMES = new Theme[]{
  new Theme(   #000000, #00FF00, #CFFFE3, #FF8A8A, #7CFF7C, #9AFFC6, #00FF00), // IBM 5151 Green
  new Theme(   #000000, #FFC04D, #FFE6B0, #FF7B5C, #FFD38A, #FFE6B0, #FFC04D), // Amber
  new Theme(   #00161A, #7FE7FF, #CDEFFF, #FF9BA1, #A5F2FF, #CDEFFF, #7FE7FF), // Cyan
  new Theme(   #0A0014, #D7A8FF, #EAD9FF, #FF9BCF, #E3C9FF, #EAD9FF, #D7A8FF), // Violet
  new Theme(   #002B36, #268BD2, #93A1A1, #DC322F, #2AA198, #839496, #268BD2), // Solarized Dark
  new Theme(   #272822, #A6E22E, #F8F8F2, #F92672, #66D9EF, #F8F8F2, #A6E22E), // Monokai
  new Theme(   #282828, #B8BB26, #EBDBB2, #FB4934, #FABD2F, #D5C4A1, #B8BB26), // Gruvbox Dark
  new Theme(   #282A36, #50FA7B, #F8F8F2, #FF5555, #BD93F9, #6272A4, #50FA7B), // Dracula
  new Theme(   #000000, #BFBFBF, #D9D9D9, #FF6666, #FFFFFF, #BFBFBF, #BFBFBF)  // Classic
};
int themeIndex = 0;
Theme curTheme = THEMES[themeIndex];

ArrayList<Step> steps = new ArrayList<Step>();
ArrayList<String> screen = new ArrayList<String>();

// prompts (filled in buildScript)
String sysPrompt = "";
String miniPrompt = "minishell$ ";

// typing/flow state
int stepIdx = 0, charIdx = 0;
int typeMinMs = 16, typeMaxMs = 38; // ↑/↓ to change typing speed
int waitAfterCmdMs = 110, waitBetweenStepsMs = 160;
int nextTypeAtMs = 0, stateUntilMs = 0;
int state = 0; // 0 typing, 1 wait-enter, 2 print outputs, 3 wait-next, 4 finished->overlay

// finale overlay (letters pulse; terminal hidden)
boolean overlayActive = false;
int overlayStartMs = 0;
int overlayDurationMs = 1100; // total overlay time (ms)
float pulseHz = 3.0;          // letter pulse frequency
float alphaMin = 90;          // min alpha during pulse
float alphaMax = 255;         // max alpha during pulse
float scaleAmp = 0.03;        // ±3% scale wobble
char[] overlayWord = "minishell".toCharArray();
float[] letterPhase = new float[overlayWord.length]; // random phase per letter

PFont mono;
float fontSize, lineHeight = 1.18f, margin = 16;
int maxLinesOnScreen;

boolean blinkOn() { return (millis() / 500) % 2 == 0; }

void setup() {
  size(720, 480);
  frameRate(30);
  mono = createFont("../IBM_Plex_Mono/IBMPlexMono-Bold.ttf", 1000);
  textFont(mono);
  textAlign(LEFT, TOP);
  surface.setTitle("minishell — old-school typer");

  buildScript();

  // aim ~26 lines visible on 720p
  float avail = height - margin * 3.3;
  fontSize = (avail / (26 * lineHeight));
  maxLinesOnScreen = int(avail / (lineHeight * fontSize));

  resetPlayback();
}

void buildScript() {
  sysPrompt  = USER + "@" + HOST + ":~" + HOME_PATH.replace("/home/" + USER, "") + "$ ";
  miniPrompt = "minishell$ ";

  steps.clear();

  // Launch minishell
  steps.add(new Step(sysPrompt, "./minishell",
    "Welcome to minishell — 42",
    "authors: " + USER + " & " + PAIR));

  // Basics & env
  steps.add(new Step(miniPrompt, "pwd", HOME_PATH));
  steps.add(new Step(miniPrompt, "echo \"" + USER + "@" + HOST + "\"", USER + "@" + HOST));
  steps.add(new Step(miniPrompt, "env | grep -E '^(USER|PWD|SHLVL)='",
    "USER=" + USER,
    "PWD=" + HOME_PATH,
    "SHLVL=2"));

  // export / unset / expansions
  steps.add(new Step(miniPrompt, "export A=42 B=1337"));
  steps.add(new Step(miniPrompt, "echo $A:$B", "42:1337"));
  steps.add(new Step(miniPrompt, "unset B; echo $B", ""));
  steps.add(new Step(miniPrompt, "echo 'single $A stays literal'", "single $A stays literal"));
  steps.add(new Step(miniPrompt, "echo \"double expands $A\"", "double expands 42"));
  steps.add(new Step(miniPrompt, "echo back\\ slash", "back\\ slash"));

  // cd & pwd
  steps.add(new Step(miniPrompt, "cd .. && pwd", HOME_PATH.substring(0, max(1, HOME_PATH.lastIndexOf('/')))));

  // pipes
  steps.add(new Step(miniPrompt, "echo -n hi | wc -c", "2"));
  steps.add(new Step(miniPrompt, "ls | head -n 3", "Makefile", "minishell.c", "parser.c"));

  // redirections
  steps.add(new Step(miniPrompt, "echo world > out.txt"));
  steps.add(new Step(miniPrompt, "echo more >> out.txt"));
  steps.add(new Step(miniPrompt, "wc -l < out.txt", "2"));

  // heredoc
  steps.add(new Step(miniPrompt, "cat << EOF | grep mini",
    "hello minishell",
    "EOF",
    "hello minishell"));

  // errors & statuses
  steps.add(new Step(miniPrompt, "cat nofile",
    "minishell: nofile: No such file or directory"));
  steps.add(new Step(miniPrompt, "echo $?", "1"));
  steps.add(new Step(miniPrompt, "| ls",
    "minishell: syntax error near unexpected token `|'"));
  steps.add(new Step(miniPrompt, "echo $?", "258"));
  steps.add(new Step(miniPrompt, "env | grep ^PATH=",
    "PATH=/usr/local/bin:...:/usr/bin"));

  // signals
  steps.add(new Step(miniPrompt, "sleep 3", "^C"));
  steps.add(new Step(miniPrompt, "echo $?", "130"));
  steps.add(new Step(miniPrompt, "sleep 3", "^\\", "Quit (core dumped)"));
  steps.add(new Step(miniPrompt, "echo $?", "131"));

  // authors file
  steps.add(new Step(miniPrompt, "cat AUTHORS", USER, PAIR));

  // exit (LAST STEP -> overlay -> theme cycle -> restart)
  steps.add(new Step(miniPrompt, "exit"));
}

void resetPlayback() {
  screen.clear();
  screen.add("42 minishell — " + USER + " & " + PAIR);
  screen.add("");
  stepIdx = 0; charIdx = 0; state = 0;
  nextTypeAtMs = millis(); stateUntilMs = 0;
  overlayActive = false;

  if (!steps.isEmpty()) screen.add(steps.get(0).prompt);
}

void startOverlay() {
  overlayActive = true;
  overlayStartMs = millis();
  for (int i = 0; i < letterPhase.length; i++) letterPhase[i] = random(TWO_PI);
}

void cycleThemeAndRestart() {
  themeIndex = (themeIndex + 1) % THEMES.length;
  curTheme = THEMES[themeIndex];
  resetPlayback();
}

void draw() {
  // If the finale overlay is active, show ONLY the effect and return.
  if (overlayActive) {
    drawOverlayOnly();
    saveFrame("frames/frame-####.png");
    return;
  }

  // Normal terminal drawing & logic
  background(curTheme.bg);
  textFont(mono);
  textSize(fontSize);
  textLeading(lineHeight * fontSize);
  textAlign(LEFT, TOP);

  // --- flow machine ---
  if (stepIdx < steps.size()) {
    Step s = steps.get(stepIdx);

    if (state == 0) { // typing
      if (millis() >= nextTypeAtMs) {
        String line = screen.get(screen.size() - 1);
        if (charIdx < s.cmd.length()) {
          line += s.cmd.charAt(charIdx++);
          screen.set(screen.size() - 1, line);
          nextTypeAtMs = millis() + int(random(typeMinMs, typeMaxMs));
        } else {
          state = 1; stateUntilMs = millis() + waitAfterCmdMs;
        }
        trimScreen();
      }
    } else if (state == 1) { // pause after enter
      if (millis() >= stateUntilMs) state = 2;
    } else if (state == 2) { // print outputs
      for (String o : s.out) { screen.add(o); trimScreen(); }
      state = 3; stateUntilMs = millis() + waitBetweenStepsMs;
    } else if (state == 3) { // advance
      if (millis() >= stateUntilMs) {
        stepIdx++;
        if (stepIdx < steps.size()) {
          Step ns = steps.get(stepIdx);
          screen.add(ns.prompt); trimScreen();
          charIdx = 0; state = 0;
        } else {
          state = 4; // finished; trigger clean overlay then theme cycle
          startOverlay();
        }
      }
    }
  }

  // --- draw terminal lines with simple tint rules ---
  float y = margin;
  for (int i = max(0, screen.size() - maxLinesOnScreen); i < screen.size(); i++) {
    String raw = screen.get(i);
    String ln = raw.trim();

    if (ln.contains("minishell —") || ln.startsWith("Welcome to minishell") || ln.startsWith("authors:")) {
      fill(curTheme.banner);
    } else if (ln.startsWith("minishell:")) {
      fill(curTheme.error);
    } else if (raw.startsWith(miniPrompt) || raw.startsWith(sysPrompt)) {
      fill(curTheme.prompt);
    } else {
      fill(curTheme.output);
    }

    text(raw, margin, y);
    y += lineHeight * fontSize;
  }

  // blinking block cursor (during typing / enter pause)
  if (state == 0 || state == 1) {
    if (blinkOn()) {
      String line = screen.get(screen.size() - 1);
      float x = margin + textWidth(line);
      float h = textAscent() + textDescent();
      noStroke(); fill(curTheme.cursor);
      rect(x + 1, (y - lineHeight * fontSize), 9, h * 0.9);
    }
  }

  // footer
  fill(curTheme.footer);
  textSize(12);
  textAlign(LEFT, TOP);
  text("R replay  •  ↑/↓ typing speed (" + typeMinMs + "-" + typeMaxMs + " ms/char)  •  theme " + (themeIndex+1) + "/" + THEMES.length,
       margin, height - margin - 12);
       
  //save frames
  saveFrame("frames/frame-####.png");
}

void drawOverlayOnly() {
  // Full clean background; no terminal content.
  background(curTheme.bg);

  // centered "minishell" with per-letter alpha + tiny scale wobble
  textFont(mono);
  textAlign(CENTER, CENTER);

  int elapsed = millis() - overlayStartMs;
  float t = elapsed / 1000.0;

  float baseSize = min(width, height) * 0.16;
  float wobble = 1.0 + scaleAmp * sin(TWO_PI * (pulseHz * 0.5) * t);
  textSize(baseSize * wobble);

  String word = "minishell";
  float totalW = textWidth(word);
  float x0 = width / 2.0 - totalW / 2.0;
  float x = x0;
  for (int i = 0; i < overlayWord.length; i++) {
    char c = overlayWord[i];
    float a = (sin(TWO_PI * pulseHz * t + letterPhase[i]) + 1) * 0.5; // 0..1
    float alpha = lerp(alphaMin, alphaMax, a);
    fill(curTheme.banner, alpha);
    text(c, x + textWidth(str(c)) / 2.0, height / 2.0);
    x += textWidth(str(c));
  }

  // subtle credit line (optional)
  textSize(14);
  fill(curTheme.footer, 180);
  text(USER + " & " + PAIR, width/2, height/2 + baseSize * 0.9);

  // end overlay -> next theme
  if (elapsed >= overlayDurationMs) {
    overlayActive = false;
    cycleThemeAndRestart();
  }
}

void trimScreen() {
  while (screen.size() > maxLinesOnScreen + 2) screen.remove(0); // +2 header lines
}

void keyPressed() {
  if (key == 'r' || key == 'R') {
    resetPlayback();
  } else if (keyCode == UP) {
    typeMinMs = min(typeMinMs + 2, 120);
    typeMaxMs = min(typeMaxMs + 2, 160);
  } else if (keyCode == DOWN) {
    typeMinMs = max(4, typeMinMs - 2);
    typeMaxMs = max(typeMinMs + 4, typeMaxMs - 2);
  }
}
