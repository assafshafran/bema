// "Present with Bema": hand the deck in front to Bema.
// PowerPoint asks "add-in wants to open Bema.app" before every link and blocks add-ins from reaching
// anything on the Mac, but it lets an add-in open a dialog. So the button opens a tiny dialog titled
// "Opening Bema…"; Bema sees it (through Accessibility), closes it and presents the deck in front.
// If Bema doesn't close it (not running, older version, no Accessibility), the button opens a bema://
// link instead, which PowerPoint asks about first. A deck saved on this Mac is passed by its path.
function bemaQuery() {
  var url = (Office.context && Office.context.document && Office.context.document.url) || "";
  if (url.indexOf("/") === 0) return "?path=" + encodeURIComponent(url);
  if (url.indexOf("file://") === 0 || url.indexOf("https://") === 0) return "?url=" + encodeURIComponent(url);
  return "";
}

function bemaLink() { return "bema://present" + bemaQuery(); }

function openLink(link) {
  // Try opening the link from the add-in first; if PowerPoint doesn't allow it, open it through the
  // system browser, which hands bema:// links to Bema.
  var opened = null;
  try { opened = window.open(link); } catch (e) { opened = null; }
  if (!opened) {
    try { Office.context.ui.openBrowserWindow(link); return; } catch (e) {}
    try { window.location.href = link; } catch (e) {}
  }
}

function presentWithBema(event) {
  var finished = false;
  function done() {
    if (finished) return;
    finished = true;
    if (event && event.completed) event.completed();
  }
  function byLink(why) {
    // Bema logs why the dialog didn't work (a short reason only).
    var link = bemaLink();
    link += (link.indexOf("?") < 0 ? "?" : "&") + "why=" + encodeURIComponent(String(why).slice(0, 200));
    try { openLink(link); } finally { done(); }
  }
  var ui = Office.context && Office.context.ui;
  if (!ui || !ui.displayDialogAsync) { byLink("no dialogs"); return; }
  ui.displayDialogAsync("https://getbema.dev/office/present.html", { height: 12, width: 18, displayInIframe: false }, function (result) {
    if (result.status !== Office.AsyncResultStatus.Succeeded) {
      byLink("dialog: " + (result.error && result.error.message));
      return;
    }
    var dialog = result.value;
    var closed = false;
    // Bema closing the dialog arrives as "the dialog was closed" (12006).
    dialog.addEventHandler(Office.EventType.DialogEventReceived, function () { closed = true; done(); });
    setTimeout(function () {
      if (closed) return;
      try { dialog.close(); } catch (e) {}
      byLink("dialog not closed by Bema");
    }, 2500);
  });
}

Office.onReady(function () {
  if (Office.actions && Office.actions.associate) Office.actions.associate("presentWithBema", presentWithBema);
});
