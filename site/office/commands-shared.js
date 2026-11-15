// "Present with Bema": hand the open deck to Bema through a bema:// link.
// A deck saved on this Mac is passed by its path; otherwise Bema takes the deck that's open in PowerPoint.
function bemaLink() {
  var url = (Office.context && Office.context.document && Office.context.document.url) || "";
  if (url.indexOf("/") === 0) return "bema://present?path=" + encodeURIComponent(url);
  if (url.indexOf("file://") === 0) return "bema://present?url=" + encodeURIComponent(url);
  return "bema://present";
}

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
  try { openLink(bemaLink()); } finally { if (event && event.completed) event.completed(); }
}

Office.onReady(function () {
  if (Office.actions && Office.actions.associate) Office.actions.associate("presentWithBema", presentWithBema);
});
