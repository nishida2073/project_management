(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function dash(s) { return s ? esc(s) : '-'; }

  var C = ClassStore.COURSES;
  var body = document.getElementById('venderBody');
  var list = ClassStore.load();

  list.forEach(function (r) {
    var c = C[r.courseCode] || { name: r.courseCode };
    var a = VenderAssignStore.find(r.id);
    var subVendors = a.subs.map(function (s) { return TeacherVenderStore.nameOf(s.vendor); }).filter(Boolean).join('、');
    var subStaffs = a.subs.map(function (s) { return StaffStore.nameOf(s.staff); }).filter(Boolean).join('、');
    var related = r.related && r.related.length ? r.related.join(', ') : '-';
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(r.year) + '</td>' +
      '<td><div style="font-weight:700;">' + esc(c.name) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(r.courseCode) + '</div></td>' +
      '<td><div style="font-weight:700;">' + esc(r.lessonNo) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(related) + '</div></td>' +
      '<td>' + esc(r.start) + '</td>' +
      '<td>' + esc(r.end) + '</td>' +
      '<td>' + dash(TeacherVenderStore.nameOf(a.mainVendor)) + '</td>' +
      '<td>' + dash(StaffStore.nameOf(a.mainStaff)) + '</td>' +
      '<td>' + dash(subVendors) + '</td>' +
      '<td>' + dash(subStaffs) + '</td>' +
      '<td class="row-actions"><a class="search-btn" href="class_vender_modify.html?id=' + encodeURIComponent(r.id) + '">編集</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('vendorFilter').setAttribute('data-options', ['すべて'].concat(TeacherVenderStore.activeNames()).join(','));
  document.getElementById('venderCount').textContent = list.length;
})();
