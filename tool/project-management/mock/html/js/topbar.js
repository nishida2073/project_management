(function () {
  var slot = document.getElementById('topbar-slot');
  if (!slot) return;
  slot.className = 'topbar';
  slot.innerHTML = '<div class="topbar-title-block"><div class="topbar-title"></div></div>' +
    '<div class="user"><span>山田 太郎（BD事業部）</span><div class="avatar">山田</div></div>';
  slot.querySelector('.topbar-title').textContent = slot.getAttribute('data-title') || '';
})();
