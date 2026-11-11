(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }
  function ownText(el) {
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
      .map(function (n) { return n.textContent; }).join('').trim();
  }
  function clean(s) { return s === '選択してください' ? '' : s; }

  function setSelect(el, name, options) {
    el.setAttribute('data-options', options.join(','));
    el.setAttribute('data-value', name || '');
    el.innerHTML = (name ? esc(name) : '選択してください') + '<span class="caret">▾</span>';
  }

  function vendorOptions() { return VendorStore.activeNames(); }
  function staffOptions() { return StaffStore.optionNames(); }

  function makeSubRow(sub) {
    var row = document.createElement('div');
    row.className = 'sub-grid sub-row';
    row.innerHTML =
      '<div class="form-control js-select" data-options="' + esc(vendorOptions().join(',')) + '">' + esc(VendorStore.nameOf(sub.vendor) || '選択してください') + '<span class="caret">▾</span></div>' +
      '<div class="form-control js-select" data-options="' + esc(staffOptions().join(',')) + '">' + esc(StaffStore.nameOf(sub.staff) || '選択してください') + '<span class="caret">▾</span></div>' +
      '<div class="sub-remove">✕</div>';
    row.querySelector('.sub-remove').addEventListener('click', function () { row.remove(); });
    $('subList').appendChild(row);
    Array.prototype.forEach.call(row.querySelectorAll('.js-select'), function (el) { window.bindJsSelect(el); });
  }

  function readSubs() {
    return Array.prototype.map.call($('subList').querySelectorAll('.sub-row'), function (row) {
      var sel = row.querySelectorAll('.js-select');
      return {
        vendor: VendorStore.codeOf(clean(ownText(sel[0]))),
        staff: StaffStore.codeOf(clean(ownText(sel[1])))
      };
    }).filter(function (s) { return s.vendor || s.staff; });
  }

  function init(opts) {
    var classId = new URLSearchParams(location.search).get('id');
    var cls = null;
    ClassStore.load().forEach(function (r) { if (r.id === classId) cls = r; });
    if (!cls) {
      alert('対象のクラスが見つかりません');
      location.href = 'class_vender_list.html';
      return;
    }
    var c = ClassStore.COURSES[cls.courseCode];
    $('subLine').textContent = cls.lessonNo + '　' + (c ? c.name : cls.courseCode) + 'の登壇管理を編集します';

    var a = VenderAssignStore.find(classId);
    setSelect($('mainVendor'), VendorStore.nameOf(a.mainVendor), vendorOptions());
    setSelect($('mainStaff'), StaffStore.nameOf(a.mainStaff), staffOptions());
    a.subs.forEach(makeSubRow);
    setSelect($('attendeeVendor'), VendorStore.nameOf(a.attendeeVendor), vendorOptions());
    setSelect($('attendee'), StaffStore.nameOf(a.attendee), staffOptions());
    setSelect($('motivationVendor'), VendorStore.nameOf(a.motivationVendor), vendorOptions());
    setSelect($('motivationStaff'), StaffStore.nameOf(a.motivationStaff), staffOptions());

    $('addSub').addEventListener('click', function () { makeSubRow({ vendor: '', staff: '' }); });

    $('saveBtn').addEventListener('click', function () {
      var record = {
        classId: classId,
        mainCount: a.mainCount,
        subCount: a.subCount,
        mainVendor: VendorStore.codeOf(clean(ownText($('mainVendor')))),
        mainStaff: StaffStore.codeOf(clean(ownText($('mainStaff')))),
        subs: readSubs(),
        attendeeVendor: VendorStore.codeOf(clean(ownText($('attendeeVendor')))),
        attendee: StaffStore.codeOf(clean(ownText($('attendee')))),
        motivationVendor: VendorStore.codeOf(clean(ownText($('motivationVendor')))),
        motivationStaff: StaffStore.codeOf(clean(ownText($('motivationStaff'))))
      };
      if (!record.mainVendor || !record.mainStaff) {
        alert('メイン講師のベンダーと講師名を入力してください');
        return;
      }
      VenderAssignStore.upsert(record);
      location.href = 'class_vender_list.html';
    });
  }

  window.VenderAssignEditor = { init: init };
})();
