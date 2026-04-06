// Split-view ASCII/SVG toggle
document.addEventListener("click", function (e) {
  var btn = e.target.closest(".split-tabs button");
  if (!btn) return;
  var view = btn.closest(".split-view");
  var target = btn.getAttribute("data-target");

  view.querySelectorAll(".split-tabs button").forEach(function (b) {
    b.classList.toggle("active", b === btn);
  });
  view.querySelectorAll(".split-panel").forEach(function (p) {
    p.classList.toggle("active", p.getAttribute("data-panel") === target);
  });
});

// TOC scroll highlight
(function () {
  var tocLinks = document.querySelectorAll(".toc a");
  if (!tocLinks.length) return;

  var headings = [];
  tocLinks.forEach(function (link) {
    var id = link.getAttribute("href");
    if (id && id.startsWith("#")) {
      var el = document.getElementById(id.slice(1));
      if (el) headings.push({ el: el, link: link });
    }
  });

  function updateToc() {
    var scrollY = window.scrollY + 80;
    var current = null;
    for (var i = 0; i < headings.length; i++) {
      if (headings[i].el.offsetTop <= scrollY) {
        current = headings[i];
      }
    }
    tocLinks.forEach(function (l) { l.classList.remove("active"); });
    if (current) current.link.classList.add("active");
  }

  window.addEventListener("scroll", updateToc, { passive: true });
  updateToc();
})();
