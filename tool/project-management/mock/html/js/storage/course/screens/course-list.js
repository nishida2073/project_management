(function () {

  var body = document.getElementById('courseBody');
  var list = CourseStore.load();

  var today = new Date();
  today.setHours(0, 0, 0, 0);
  var endedCount = {};
  ClassStore.load().forEach(function (r) {
    var end = new Date(String(r.end).replace(/\//g, '-'));
    if (!isNaN(end.getTime()) && end < today) endedCount[r.courseCode] = (endedCount[r.courseCode] || 0) + 1;
  });

  list.forEach(function (c) {
    var planned = CourseStore.planned(c);
    var actual = endedCount[c.code] || 0;
    var on = c.status !== OperatingStatusStore.nameOf('STOPPED');
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td class="sticky">' + esc(yearLabel(c.year)) + '</td>' +
      '<td class="sticky">' + esc(c.code) + '</td>' +
      '<td class="sticky"><span class="tag participation-type-tag ' + ParticipationTypeStore.colorOf(c.part) + '">' + esc(ParticipationTypeStore.nameOf(c.part)) + '</span></td>' +
      '<td class="sticky">' + esc(c.name) + '</td>' +
      (c.delivery ? '<td><span class="tag delivery-type-tag ' + DeliveryTypeStore.colorOf(c.delivery) + '">' + esc(DeliveryTypeStore.nameOf(c.delivery)) + '</span></td>' : '<td>-</td>') +
      '<td>' + dashOr(c.days, '日') + '</td>' +
      '<td>' + dashOr(c.min, '人') + '</td>' +
      '<td>' + dashOr(c.max, '人') + '</td>' +
      '<td>' + dashOr(c.mainTeachers, '人') + '</td>' +
      '<td>' + dashOr(c.subTeachers, '人') + '</td>' +
      '<td>' + dashOr(c.specialTeachers, '人') + '</td>' +
      '<td>' + esc(actual) + '/' + planned + 'クラス</td>' +
      '<td><span class="status-label ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.nameOf('ACTIVE') : OperatingStatusStore.nameOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (c.memo ? ' data-memo="' + esc(c.memo) + '"' : '') + '>' + (c.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="nav-btn" href="course_modify.html?id=' + encodeURIComponent(c.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('courseCount').textContent = list.length;
})();
