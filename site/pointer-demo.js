// The interactive pointer-tools demo on the home page: the same tools as Bema's toolbar,
// drawn on a canvas over the demo slide. Plain JavaScript, no dependencies.
(function () {
  var root = document.getElementById("pointer-demo");
  if (!root) return;
  var stage = root.querySelector(".dstage");
  var img = stage.querySelector("img");
  var canvas = stage.querySelector("canvas");
  var ctx = canvas.getContext("2d");
  var buttons = Array.prototype.slice.call(root.querySelectorAll("[data-tool]"));
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  var state = {
    tool: "laser", pointer: null, down: false, strokes: [], active: null, stamps: [],
    stampKinds: ["✓", "✗", "★", "○"], stampNext: 0, trail: [], particles: [], black: false
  };

  function size() {
    if (typeof draw === "function" && canvas.width) setTimeout(function () { draw(performance.now()); }, 0);
    var r = stage.getBoundingClientRect(), d = window.devicePixelRatio || 1;
    canvas.width = Math.round(r.width * d); canvas.height = Math.round(r.height * d);
    canvas.style.width = r.width + "px"; canvas.style.height = r.height + "px";
    ctx.setTransform(d, 0, 0, d, 0, 0);
  }
  function W() { return canvas.width / (window.devicePixelRatio || 1); }
  function H() { return canvas.height / (window.devicePixelRatio || 1); }
  function pt(e) {
    var r = stage.getBoundingClientRect();
    return { x: (e.clientX - r.left) / r.width, y: (e.clientY - r.top) / r.height };
  }

  // Draw now as well as on the animation loop, which browsers pause for background tabs.
  function redraw() { draw(performance.now()); }

  function select(tool) {
    if (tool === "clear") { state.strokes = []; state.stamps = []; redraw(); return; }
    if (tool === "react") { burst(); return; }
    if (tool === "black") { state.black = !state.black; mark(); redraw(); return; }
    state.tool = tool;
    stage.style.cursor = tool === "pointer" ? "default" : (tool === "magnifier" || tool === "spotlight" ? "none" : "crosshair");
    mark();
    redraw();
  }
  function mark() {
    buttons.forEach(function (b) {
      var t = b.getAttribute("data-tool");
      var on = t === state.tool || (t === "black" && state.black);
      b.classList.toggle("on", on);
      b.setAttribute("aria-pressed", on ? "true" : "false");
    });
  }

  function burst() {
    if (reduceMotion) return;
    var colors = ["#F5A524", "#FF5A4F", "#4BE3A0", "#5B9DFF", "#C792EA", "#FFFFFF"];
    for (var i = 0; i < 120; i++) {
      state.particles.push({
        x: Math.random(), y: -0.05 - Math.random() * 0.2, vx: (Math.random() - 0.5) * 0.25,
        vy: 0.15 + Math.random() * 0.35, r: Math.random() * 6, spin: (Math.random() - 0.5) * 12,
        w: 6 + Math.random() * 8, c: colors[i % colors.length], t0: performance.now() + Math.random() * 500
      });
    }
  }

  // Input
  stage.addEventListener("pointermove", function (e) {
    var p = pt(e);
    state.pointer = p;
    state.trail.push({ x: p.x, y: p.y, t: performance.now() });
    if (state.down && state.active) state.active.points.push(p);
    redraw();
  });
  stage.addEventListener("pointerleave", function () { state.pointer = null; redraw(); });
  stage.addEventListener("pointerdown", function (e) {
    var p = pt(e);
    state.pointer = p;
    if (state.tool === "pen" || state.tool === "highlighter") {
      state.down = true;
      state.active = { tool: state.tool, points: [p] };
      state.strokes.push(state.active);
      stage.setPointerCapture(e.pointerId);
      e.preventDefault();
    } else if (state.tool === "stamp") {
      state.stamps.push({ x: p.x, y: p.y, k: state.stampKinds[state.stampNext++ % state.stampKinds.length] });
    }
    redraw();
  });
  function up() { state.down = false; state.active = null; }
  stage.addEventListener("pointerup", up);
  stage.addEventListener("pointercancel", up);
  buttons.forEach(function (b) { b.addEventListener("click", function () { select(b.getAttribute("data-tool")); }); });

  // Same keys as the app, while the demo is on screen.
  var visible = false;
  document.addEventListener("keydown", function (e) {
    if (!visible || e.metaKey || e.ctrlKey || e.altKey) return;
    var tag = (document.activeElement && document.activeElement.tagName) || "";
    if (tag === "INPUT" || tag === "TEXTAREA") return;
    var map = { l: "laser", s: "spotlight", m: "magnifier", p: "pen", h: "highlighter", t: "stamp", e: "clear", b: "black", "1": "react" };
    var t = map[e.key.toLowerCase()];
    if (t) { select(t); e.preventDefault(); }
  });

  // Drawing
  function strokePath(points) {
    ctx.beginPath();
    points.forEach(function (q, i) { var x = q.x * W(), y = q.y * H(); if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y); });
    if (points.length === 1) ctx.lineTo(points[0].x * W() + 0.1, points[0].y * H());
  }
  function draw(now) {
    var w = W(), h = H();
    ctx.clearRect(0, 0, w, h);
    ctx.lineCap = "round"; ctx.lineJoin = "round";
    state.strokes.forEach(function (s) {
      strokePath(s.points);
      if (s.tool === "highlighter") { ctx.strokeStyle = "rgba(255,235,0,0.42)"; ctx.lineWidth = Math.max(w * 0.022, 8); }
      else { ctx.strokeStyle = "#E5352B"; ctx.lineWidth = Math.max(w * 0.0035, 2.5); }
      ctx.stroke();
    });
    state.stamps.forEach(function (s) {
      var r = Math.max(w * 0.03, 14), x = s.x * w, y = s.y * h;
      if (s.k === "○") { ctx.strokeStyle = "#E5352B"; ctx.lineWidth = Math.max(w * 0.005, 3); ctx.beginPath(); ctx.ellipse(x, y, r * 1.3, r * 0.85, 0, 0, Math.PI * 2); ctx.stroke(); return; }
      ctx.fillStyle = s.k === "✓" ? "#2FBF71" : s.k === "✗" ? "#E5352B" : "#F5B301";
      ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = "#fff"; ctx.font = "bold " + Math.round(r * 1.15) + "px system-ui, sans-serif";
      ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(s.k, x, y + r * 0.05);
    });

    var p = state.pointer;
    if (p) {
      var x = p.x * w, y = p.y * h;
      if (state.tool === "laser") {
        state.trail = state.trail.filter(function (t) { return now - t.t < 350; });
        state.trail.forEach(function (t) {
          var a = 1 - (now - t.t) / 350;
          ctx.fillStyle = "rgba(255,42,31," + (0.25 * a) + ")";
          ctx.beginPath(); ctx.arc(t.x * w, t.y * h, 6 * a + 2, 0, Math.PI * 2); ctx.fill();
        });
        var g = ctx.createRadialGradient(x, y, 0, x, y, 22);
        g.addColorStop(0, "rgba(255,42,31,0.55)"); g.addColorStop(1, "rgba(255,42,31,0)");
        ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, 22, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = "#FF2A1F"; ctx.beginPath(); ctx.arc(x, y, 6, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = "rgba(255,255,255,0.8)"; ctx.beginPath(); ctx.arc(x, y, 2.2, 0, Math.PI * 2); ctx.fill();
      } else if (state.tool === "spotlight") {
        var r = Math.max(w * 0.12, 60);
        ctx.save();
        ctx.fillStyle = "rgba(0,0,0,0.68)"; ctx.fillRect(0, 0, w, h);
        ctx.globalCompositeOperation = "destination-out";
        var sg = ctx.createRadialGradient(x, y, r * 0.8, x, y, r);
        sg.addColorStop(0, "rgba(0,0,0,1)"); sg.addColorStop(1, "rgba(0,0,0,0)");
        ctx.fillStyle = sg; ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
        ctx.restore();
      } else if (state.tool === "magnifier" && img.complete && img.naturalWidth) {
        var mr = Math.max(w * 0.11, 55), z = 2.2;
        ctx.save();
        ctx.shadowColor = "rgba(0,0,0,0.45)"; ctx.shadowBlur = 16;
        ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.arc(x, y, mr, 0, Math.PI * 2); ctx.fill();
        ctx.shadowBlur = 0;
        ctx.beginPath(); ctx.arc(x, y, mr, 0, Math.PI * 2); ctx.clip();
        ctx.drawImage(img, x - p.x * w * z, y - p.y * h * z, w * z, h * z);
        ctx.restore();
        ctx.strokeStyle = "#fff"; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(x, y, mr, 0, Math.PI * 2); ctx.stroke();
      } else if (state.tool === "stamp") {
        ctx.globalAlpha = 0.4;
        ctx.fillStyle = "#2FBF71"; ctx.beginPath(); ctx.arc(x, y, Math.max(w * 0.03, 14), 0, Math.PI * 2); ctx.fill();
        ctx.globalAlpha = 1;
      }
    }

    state.particles = state.particles.filter(function (q) { return now - q.t0 < 3200; });
    state.particles.forEach(function (q) {
      var t = (now - q.t0) / 1000;
      if (t < 0) return;
      var px = (q.x + q.vx * t) * w, py = (q.y + q.vy * t + 0.18 * t * t) * h;
      ctx.save(); ctx.translate(px, py); ctx.rotate(q.r + q.spin * t);
      ctx.globalAlpha = Math.min(1, (3.2 - t) / 0.6);
      ctx.fillStyle = q.c; ctx.fillRect(-q.w / 2, -q.w / 4, q.w, q.w / 2);
      ctx.restore();
    });

    if (state.black) {
      ctx.fillStyle = "#000"; ctx.fillRect(0, 0, w, h);
      ctx.fillStyle = "rgba(255,255,255,0.55)"; ctx.font = "500 14px system-ui, sans-serif";
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.fillText("The audience sees black. Press B again.", w / 2, h / 2);
    }
  }

  var running = false;
  function loop(now) { draw(now); if (running) requestAnimationFrame(loop); }
  new IntersectionObserver(function (entries) {
    visible = entries[0].isIntersecting;
    if (visible && !running) { running = true; requestAnimationFrame(loop); }
    if (!visible) running = false;
  }).observe(stage);

  size();
  window.addEventListener("resize", size);
  if (window.ResizeObserver) new ResizeObserver(size).observe(stage);
  select("laser");
})();
