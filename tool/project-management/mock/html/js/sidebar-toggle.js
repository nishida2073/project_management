(function () {
  var app = document.querySelector('.app');
  if (!app) return;
  var KEY = 'sidebarClosed';
  function load() {
    try { return localStorage.getItem(KEY) === '1'; } catch (e) { return false; }
  }
  function save(closed) {
    try { localStorage.setItem(KEY, closed ? '1' : '0'); } catch (e) {}
  }
  if (load()) app.classList.add('sidebar-closed');
  window.addEventListener('message', function (e) {
    if (e.data && e.data.type === 'sidebar-toggle') {
      app.classList.toggle('sidebar-closed');
      save(app.classList.contains('sidebar-closed'));
    }
  });
})();

window.addEventListener('message', function (e) {
  if (e.data && e.data.type === 'reset-storage') {
    try { localStorage.clear(); } catch (err) {}
    location.reload();
  }
});
