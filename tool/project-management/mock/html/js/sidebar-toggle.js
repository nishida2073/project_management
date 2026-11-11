(function () {
  var app = document.querySelector('.app');
  if (!app) return;
  window.addEventListener('message', function (e) {
    if (e.data && e.data.type === 'sidebar-toggle') {
      app.classList.toggle('sidebar-closed');
    }
  });
})();
