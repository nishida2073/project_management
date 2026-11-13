(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function dash(s) { return s ? esc(s) : '-'; }

  var C = ClassStore.COURSES;
  var body = document.getElementById('venderBody');
  var list = ClassStore.load().filter(function (r) { return r.status !== '停止中'; });

  list.forEach(function (r) {
    var c = C[r.courseCode] || { name: r.courseCode };
    var a = VenderAssignStore.find(r.id);
    function lines(items) {
      return items.length ? items.map(function (x) {
        return '<div>' + esc(x.vendor) + '：' + esc(x.staff) + '</div>';
      }).join('') : '-';
    }
    var mainLines = lines(a.mains.map(function (m) {
      return { vendor: TeacherVenderStore.nameOf(m.vendor) || '-', staff: m.staff || '-' };
    }));
    var subLines = lines(a.subs.map(function (s) {
      return { vendor: TeacherVenderStore.nameOf(s.vendor) || '-', staff: s.staff || '-' };
    }));
    var related = r.related && r.related.length ? r.related.join(', ') : '-';
    var planMain = parseInt(r.mainTeachers, 10) || 0;
    var planSub = parseInt(r.subTeachers, 10) || 0;
    var zan = a.mains.length < planMain || a.subs.length < planSub;
    var ps = ClassStore.practiceStatus(r);
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + (ps ? '<span class="tag ' + ClassStore.PRACTICE_CLASS[ps] + '">' + ps + '</span>' : '') + '</td>' +
      '<td>' + esc(r.year) + '</td>' +
      '<td><div>' + esc(c.name) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(r.courseCode) + '</div></td>' +
      '<td><div>' + esc(r.lessonNo) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(related) + '</div></td>' +
      '<td>' + esc(r.start) + '</td>' +
      '<td>' + esc(r.end) + '</td>' +
      '<td>' + (r.mainTeachers ? esc(r.mainTeachers) + '名' : '-') + '</td>' +
      '<td>' + (r.subTeachers ? esc(r.subTeachers) + '名' : '-') + '</td>' +
      '<td>' + (zan ? '<span class="tag orange">あり</span>' : '<span class="tag green">なし</span>') + '</td>' +
      '<td>' + mainLines + '</td>' +
      '<td>' + subLines + '</td>' +
      '<td class="row-actions"><a class="search-btn" href="class_vender_modify.html?id=' + encodeURIComponent(r.id) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('vendorFilter').setAttribute('data-options', ['すべて'].concat(TeacherVenderStore.activeNames()).join(','));
  document.getElementById('venderCount').textContent = list.length;
  window.addEventListener('load', function () {
    var btn = document.querySelector('.filter-panel .search-btn');
    if (btn) btn.click();
  });
})();
