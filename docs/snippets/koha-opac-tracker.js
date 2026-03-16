// Matomo OPAC tracker snippet (managed by koha-deploy IaC patch module)
var _paq = window._paq = window._paq || [];
_paq.push(["disableCookies"]);
_paq.push(['setDoNotTrack', true]);

var _kohaDeviceType = window.matchMedia('(max-width: 767px)').matches ? 'Mobile' : 'Desktop';
_paq.push(['setCustomDimension', __MATOMO_DEVICE_DIMENSION_ID__, _kohaDeviceType]);

function enableSiteSearch(param) {
  try {
    var keyword = new URLSearchParams(window.location.search).get(param);
    if (keyword) {
      _paq.push(['trackSiteSearch', keyword, false, false]);
    }
  } catch (error) {
  }
}

enableSiteSearch('__MATOMO_SITE_SEARCH_QUERY_PARAM__');

_paq.push(['enableLinkTracking']);
(function() {
  var u="__MATOMO_BASE_URL__";
  _paq.push(['setTrackerUrl', '__MATOMO_TRACKER_URL__']);
  _paq.push(['setSiteId', '__MATOMO_SITE_ID__']);
  _paq.push(['trackPageView']);
  var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0];
  g.async=true; g.src=u+'matomo.js'; s.parentNode.insertBefore(g,s);
})();
