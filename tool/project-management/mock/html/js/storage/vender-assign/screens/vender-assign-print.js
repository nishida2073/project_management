(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }

  var C = ClassStore.COURSES;
  var list = ClassStore.load();
  var body = $('printBody');
  var rows = [];

  list.forEach(function (r) {
    var a = VenderAssignStore.find(r.id);
    rows.push({ cls: r, assign: a });
    var c = C[r.courseCode] || { name: r.courseCode };
    var tr = document.createElement('tr');
    tr.setAttribute('data-id', r.id);
    tr.innerHTML =
      '<td>' + esc(r.year) + '</td>' +
      '<td><div style="font-weight:700;">' + esc(c.name) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(r.courseCode) + '</div></td>' +
      '<td><div style="font-weight:700;">' + esc(r.lessonNo) + '</div></td>' +
      '<td>' + esc(r.start) + '</td>' +
      '<td>' + esc(r.end) + '</td>' +
      '<td><input type="number" class="form-control main-count" min="0" value="' + esc(a.mainCount) + '" style="width:72px;"></td>' +
      '<td><input type="number" class="form-control sub-count" min="0" value="' + esc(a.subCount) + '" style="width:72px;"></td>';
    body.appendChild(tr);
  });

  $('printCount').textContent = list.length;

  $('bulkApply').addEventListener('click', function () {
    var main = $('bulkMain').value;
    var sub = $('bulkSub').value;
    body.querySelectorAll('.main-count').forEach(function (i) { i.value = main; });
    body.querySelectorAll('.sub-count').forEach(function (i) { i.value = sub; });
  });

  function requestHtml(r, a, mainCount, subCount) {
    var c = C[r.courseCode] || { name: r.courseCode };
    var subs = a.subs.map(function (s) {
      return VendorStore.nameOf(s.vendor) + ' ' + StaffStore.nameOf(s.staff);
    }).join('、') || '-';
    var main = (VendorStore.nameOf(a.mainVendor) || '-') + ' ' + (StaffStore.nameOf(a.mainStaff) || '');
    var attendee = (VendorStore.nameOf(a.attendeeVendor) || '-') + ' ' + (StaffStore.nameOf(a.attendee) || '');
    return '<tr>' +
      '<td>' + esc(c.name) + '<br>' + esc(r.courseCode) + '</td>' +
      '<td>' + esc(r.lessonNo) + '</td>' +
      '<td>' + esc(r.start) + '〜' + esc(r.end) + '</td>' +
      '<td>' + esc(r.locationName ? LocationStore.nameOf(r.locationName) : '') + '</td>' +
      '<td>' + esc(main) + '（' + mainCount + '名）</td>' +
      '<td>' + esc(subs) + '（' + subCount + '名）</td>' +
      '<td>' + esc(attendee) + '</td>' +
      '</tr>';
  }

  $('printBtn').addEventListener('click', function () {
    var lines = [];
    body.querySelectorAll('tr').forEach(function (tr) {
      var id = tr.getAttribute('data-id');
      var row = rows.filter(function (x) { return x.cls.id === id; })[0];
      if (!row) return;
      var mainCount = parseInt(tr.querySelector('.main-count').value, 10) || 0;
      var subCount = parseInt(tr.querySelector('.sub-count').value, 10) || 0;
      var a = Object.assign({}, row.assign, { mainCount: mainCount, subCount: subCount });
      VenderAssignStore.upsert(a);
      lines.push(requestHtml(row.cls, a, mainCount, subCount));
    });
    $('printArea').innerHTML =
      '<h2>登壇依頼書</h2>' +
      '<table><thead><tr><th>コース</th><th>レッスンNo</th><th>日程</th><th>会場</th><th>メイン講師</th><th>サブ講師</th><th>聴講</th></tr></thead>' +
      '<tbody>' + lines.join('') + '</tbody></table>';
    window.print();
  });
})();
