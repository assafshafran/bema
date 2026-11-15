// The detached-prompter illustration on the home page: switch between your screen and what a
// screen share shows, while the prompter's current word moves along as if you were speaking.
(function () {
  var root = document.getElementById("share-demo");
  if (!root) return;
  var scene = root.querySelector(".pscene");
  var buttons = Array.prototype.slice.call(root.querySelectorAll(".pv"));
  buttons.forEach(function (b) {
    b.addEventListener("click", function () {
      var v = b.getAttribute("data-view");
      scene.setAttribute("data-view", v);
      buttons.forEach(function (x) {
        var on = x === b;
        x.classList.toggle("on", on);
        x.setAttribute("aria-pressed", on ? "true" : "false");
      });
    });
  });

  // The script, a line at a time; the amber word steps forward like the voice prompter.
  var lines = [
    "Welcome everyone. Tonight I want to",
    "talk about the part of presenting",
    "that AI has barely touched yet.",
    "Making slides got easy. Standing up",
    "and giving the talk is still hard."
  ];
  var line = 0, word = 0;
  var pline = document.getElementById("pline"), pnext = document.getElementById("pnext");
  if (!pline || !pnext) return;
  if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
  function render() {
    var words = lines[line].split(" ");
    pline.innerHTML = words.map(function (w, i) {
      return i < word ? '<span style="color:#8A93A0">' + esc(w) + "</span>" : i === word ? "<b>" + esc(w) + "</b>" : esc(w);
    }).join(" ");
    pnext.textContent = lines[(line + 1) % lines.length];
  }
  var visible = false;
  new IntersectionObserver(function (e) { visible = e[0].isIntersecting; }).observe(scene);
  setInterval(function () {
    if (!visible) return;
    word++;
    if (word >= lines[line].split(" ").length) { word = 0; line = (line + 1) % lines.length; }
    render();
  }, 380);
  render();
})();
