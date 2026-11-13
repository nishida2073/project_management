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
    var S = VenderAssignStore.STATUS;
    function lines(items) {
      return items.length ? items.map(function (x) {
        return '<div>' + esc(x.vendor) + '：' + esc(x.staff) + (x.status ? ' ' + VenderAssignStore.tag(x.status) : '') + '</div>';
      }).join('') : '-';
    }
    var mainLines = lines(a.mains.map(function (m) {
      return { vendor: TeacherVenderStore.nameOf(m.vendor) || '-', staff: m.staff || '', status: m.staff ? S.REQUESTED : S.BEFORE };
    }));
    var subLines = lines(a.subs.map(function (s) {
      return { vendor: TeacherVenderStore.nameOf(s.vendor) || '-', staff: s.staff || '', status: s.staff ? S.REQUESTED : S.BEFORE };
    }));
    var reqs = VenderAssignStore.requestsOf(a);
    var tot = VenderAssignStore.totalRequest(a);
    reqs.forEach(function (rq) {
      var reqText = esc(TeacherVenderStore.nameOf(rq.vendor) || '-') + '： ' + VenderAssignStore.tag(S.REQUESTING);
      for (var mi = 0; mi < (rq.main || 0); mi++) mainLines = (mainLines === '-' ? '' : mainLines) + '<div>' + reqText + '</div>';
      for (var si = 0; si < (rq.sub || 0); si++) subLines = (subLines === '-' ? '' : subLines) + '<div>' + reqText + '</div>';
    });
    var related = r.related && r.related.length ? r.related.join(', ') : '-';
    var planMain = parseInt(r.mainTeachers, 10) || 0;
    var planSub = parseInt(r.subTeachers, 10) || 0;
    var freeMain = Math.max(0, planMain - a.mains.length - tot.main);
    var freeSub = Math.max(0, planSub - a.subs.length - tot.sub);
    for (var fm = 0; fm < freeMain; fm++) mainLines = (mainLines === '-' ? '' : mainLines) + '<div>' + VenderAssignStore.tag(S.OPEN) + '</div>';
    for (var fs = 0; fs < freeSub; fs++) subLines = (subLines === '-' ? '' : subLines) + '<div>' + VenderAssignStore.tag(S.OPEN) + '</div>';
    var remMain = Math.max(0, planMain - a.mains.length);
    var remSub = Math.max(0, planSub - a.subs.length);
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
      '<td>' + remMain + '名</td>' +
      '<td>' + remSub + '名</td>' +
      '<td>' + (zan ? '<span class="tag orange">あり</span>' : '<span class="tag green">なし</span>') + '</td>' +
      '<td>' + (reqs.length ? tot.main + '名' : '-') + '</td>' +
      '<td>' + (reqs.length ? tot.sub + '名' : '-') + '</td>' +
      '<td>' + mainLines + '</td>' +
      '<td>' + subLines + '</td>' +
      '<td class="row-actions"><a class="search-btn" href="vender_assign_modify.html?id=' + encodeURIComponent(r.id) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('vendorFilter').setAttribute('data-options', ['すべて'].concat(TeacherVenderStore.activeNames()).join(','));
  document.getElementById('venderCount').textContent = list.length;
  window.addEventListener('load', function () {
    var btn = document.querySelector('.filter-panel .search-btn');
    if (btn) btn.click();
  });
})();
