(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  var P = ClassStore.PROJECTS;
  var C = ClassStore.COURSES;
  var LOCATION_CLASS = {};
  LocationTypeStore.load().forEach(function (t) { LOCATION_CLASS[t.code] = t.color; });

  var body = document.getElementById('classBody');
  var list = ClassStore.load();

  var PRACTICE_CLASS = ClassStore.PRACTICE_CLASS;

  list.forEach(function (r) {
    var p = P[r.projectCode] || { name: '', sales: '', part: '' };
    var c = C[r.courseCode] || { name: '', part: '', delivery: '', schedule: '' };
    var relatedText = r.related && r.related.length ? r.related.join(', ') : '-';
    var ps = ClassStore.practiceStatus(r);

    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + (ps ? '<span class="tag ' + PRACTICE_CLASS[ps] + '">' + ps + '</span>' : '') + '</td>' +
      '<td>' + esc(r.year) + '</td>' +
      '<td><div>' + esc(p.name) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(r.projectCode) + '</div></td>' +
      '<td>' + (p.sales ? '<span class="tag ' + SalesTypeStore.colorOf(p.sales) + '">' + esc(SalesTypeStore.nameOf(p.sales)) + '</span>' : '') + '</td>' +
      '<td>' + (p.part ? '<span class="tag ' + ParticipationTypeStore.colorOf(p.part) + '">' + esc(ParticipationTypeStore.nameOf(p.part)) + '</span>' : '') + '</td>' +
      '<td><div>' + esc(c.name) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(r.courseCode) + '</div></td>' +
      '<td><div>' + esc(r.lessonNo) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(relatedText) + '</div></td>' +
      '<td>' + (r.taskType ? '<span class="tag ' + TaskTypeStore.colorOf(r.taskType) + '">' + esc(TaskTypeStore.nameOf(r.taskType)) + '</span>' : '') + '</td>' +
      '<td>' + esc(r.start) + '</td>' +
      '<td>' + esc(r.end) + '</td>' +
      '<td>' + (r.delivery ? '<span class="tag ' + DeliveryTypeStore.colorOf(r.delivery) + '">' + esc(DeliveryTypeStore.nameOf(r.delivery)) + '</span>' : '') + '</td>' +
      '<td>' + (r.people ? esc(r.people) + '名' : '') + '</td>' +
      '<td>' + (r.mainTeachers ? esc(r.mainTeachers) + '名' : '-') + '</td>' +
      '<td>' + (r.subTeachers ? esc(r.subTeachers) + '名' : '-') + '</td>' +
      '<td>' + (r.managers || []).map(function (c) { return esc(StaffStore.nameOf(c)); }).join('<br>') + '</td>' +
      '<td>' + (r.locationType ? '<span class="tag ' + (LOCATION_CLASS[r.locationType] || '') + '">' + esc(LocationTypeStore.nameOf(r.locationType)) + '</span>' : '') + '</td>' +
      '<td>' + esc(LocationStore.nameOf(r.locationName)) + '</td>' +
      '<td><span class="badge overall-badge ' + (r.status === '停止中' ? 'gray' : 'green') + '">' + (r.status === '停止中' ? '停止中' : '稼働中') + '</span></td>' +
      '<td class="row-actions"><a class="search-btn" href="class_modify.html?id=' + encodeURIComponent(r.id) + '">編集</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('classCount').textContent = list.length;
})();
