(function () {
  window.datafast = window.datafast || function () {
    window.datafast.q = window.datafast.q || [];
    window.datafast.q.push(arguments);
  };

  var downloadPattern = /Qelvora-([0-9.]+)\.dmg/i;

  function goal(name, params) {
    try {
      window.datafast(name, params || {});
    } catch (_) {
      // Analytics should never block navigation.
    }
  }

  function placementFor(link) {
    if (link.closest(".site-header")) return "nav";
    if (link.closest(".hero")) return "hero";
    if (link.closest(".ocr-section")) return "discord_ocr";
    if (link.closest(".video-section")) return "demo";
    if (link.closest(".release-section")) return "release";
    if (link.closest(".article-cta")) return "article_cta";
    if (link.closest(".site-footer")) return "footer";
    return "unknown";
  }

  function trackDownload(event) {
    var link = event.currentTarget;
    var href = link.href;
    var versionMatch = href.match(downloadPattern);
    var params = {
      version: versionMatch ? versionMatch[1] : "latest",
      page_path: window.location.pathname,
      placement: placementFor(link),
      link_text: (link.textContent || "").trim().slice(0, 120)
    };

    goal("download_clicked", params);

    if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || link.target === "_blank") {
      return;
    }

    event.preventDefault();
    window.setTimeout(function () {
      window.location.href = href;
    }, 120);
  }

  function trackSimpleClick(name, link) {
    goal(name, {
      page_path: window.location.pathname,
      link_text: (link.textContent || "").trim().slice(0, 120),
      href: link.getAttribute("href") || ""
    });
  }

  function bind() {
    document.querySelectorAll('a[href*="/releases/latest/download/Qelvora-"]').forEach(function (link) {
      link.addEventListener("click", trackDownload);
      link.setAttribute("data-analytics-goal", "download_clicked");
    });

    document.querySelectorAll('a[href*="github.com/CyrilDieumegard/Qelvora"]').forEach(function (link) {
      if (link.href.indexOf("/releases/latest/download/") !== -1) return;
      link.addEventListener("click", function () {
        trackSimpleClick("github_clicked", link);
      });
    });

    document.querySelectorAll(".article-card[href]").forEach(function (link) {
      link.addEventListener("click", function () {
        trackSimpleClick("blog_article_clicked", link);
      });
    });

    document.querySelectorAll(".ocr-guide-link[href]").forEach(function (link) {
      link.addEventListener("click", function () {
        trackSimpleClick("discord_ocr_guide_clicked", link);
      });
    });

    document.querySelectorAll(".product-hunt-badge[href]").forEach(function (link) {
      link.addEventListener("click", function () {
        trackSimpleClick("product_hunt_clicked", link);
      });
      link.setAttribute("data-analytics-goal", "product_hunt_clicked");
    });

    var screenTextSection = document.querySelector("#screen-text");
    if (screenTextSection && "IntersectionObserver" in window) {
      var screenTextViewed = false;
      var observer = new IntersectionObserver(function (entries) {
        if (screenTextViewed || !entries.some(function (entry) { return entry.isIntersecting; })) return;
        screenTextViewed = true;
        goal("discord_ocr_section_viewed", { page_path: window.location.pathname });
        observer.disconnect();
      }, { threshold: 0.35 });
      observer.observe(screenTextSection);
    }

    document.querySelectorAll("video[data-analytics-video]").forEach(function (video) {
      var played = false;
      video.addEventListener("play", function () {
        if (played) return;
        played = true;
        goal("product_video_played", {
          page_path: window.location.pathname,
          video_id: video.getAttribute("data-analytics-video") || "product_demo"
        });
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bind);
  } else {
    bind();
  }
})();
