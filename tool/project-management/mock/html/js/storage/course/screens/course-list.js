(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

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
    var on = c.status !== '停止中';
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(String(c.year).replace('年度', '') + '年度') + '</td>' +
      '<td>' + esc(c.code) + '</td>' +
      '<td><span class="tag ' + ParticipationTypeStore.colorOf(c.part) + '">' + esc(ParticipationTypeStore.nameOf(c.part)) + '</span></td>' +
      '<td>' + esc(c.name) + '</td>' +
      '<td><span class="tag ' + DeliveryTypeStore.colorOf(c.delivery) + '">' + esc(DeliveryTypeStore.nameOf(c.delivery)) + '</span></td>' +
      '<td>' + esc(c.days) + '日</td>' +
      '<td>' + esc(c.min) + '人</td>' +
      '<td>' + esc(c.max) + '人</td>' +
      '<td>' + esc(actual) + '/' + planned + 'クラス</td>' +
      '<td><span class="badge overall-badge ' + (on ? 'green' : 'gray') + '">' + (on ? '稼働中' : '停止中') + '</span></td>' +
      '<td class="row-actions"><a class="search-btn" href="course_modify.html?id=' + encodeURIComponent(c.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('courseCount').textContent = list.length;
})();
