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

  function vendorOptions() { return TeacherVenderStore.activeNames(); }
  function staffOptions() { return StaffStore.activeNames(); }

  function makeRow(listId, data) {
    var row = document.createElement('div');
    row.className = 'sub-grid sub-row';
    row.innerHTML =
      '<div class="form-control js-select" data-options="' + esc(vendorOptions().join(',')) + '">' + esc(TeacherVenderStore.nameOf(data.vendor) || '選択してください') + '<span class="caret">▾</span></div>' +
      '<input type="text" class="form-control" placeholder="講師名" value="' + esc(data.staff || '') + '">' +
      '<div class="sub-remove">✕</div>';
    row.querySelector('.sub-remove').addEventListener('click', function () { row.remove(); });
    $(listId).appendChild(row);
    Array.prototype.forEach.call(row.querySelectorAll('.js-select'), function (el) { window.bindJsSelect(el); });
  }

  function readRows(listId) {
    return Array.prototype.map.call($(listId).querySelectorAll('.sub-row'), function (row) {
      var sel = row.querySelectorAll('.js-select');
      return {
        vendor: TeacherVenderStore.codeOf(clean(ownText(sel[0]))),
        staff: (row.querySelector('input[type="text"]') || { value: '' }).value.trim()
      };
    }).filter(function (r) { return r.vendor || r.staff; });
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
    $('subLine').textContent = cls.lessonNo + '　' + (c ? c.name : cls.courseCode) + 'の登壇管理を編集します　予定講師数：メイン' + (cls.mainTeachers || '-') + '名・サブ' + (cls.subTeachers || '-') + '名';

    var a = VenderAssignStore.find(classId);
    var zanNow = a.mains.length < (parseInt(cls.mainTeachers, 10) || 0) || a.subs.length < (parseInt(cls.subTeachers, 10) || 0);
    var zanTag = document.createElement('span');
    zanTag.className = 'tag ' + (zanNow ? 'orange' : 'green');
    zanTag.textContent = zanNow ? 'あり' : 'なし';
    $('subLine').appendChild(document.createTextNode('　依頼残：'));
    $('subLine').appendChild(zanTag);
    var planMain = parseInt(cls.mainTeachers, 10) || 0;
    var planSub = parseInt(cls.subTeachers, 10) || 0;
    var mainRows = a.mains.slice();
    while (mainRows.length < planMain) mainRows.push({ vendor: '', staff: '' });
    var subRows = a.subs.slice();
    while (subRows.length < planSub) subRows.push({ vendor: '', staff: '' });
    mainRows.forEach(function (m) { makeRow('mainList', m); });
    subRows.forEach(function (s) { makeRow('subList', s); });
    setSelect($('attendeeVendor'), TeacherVenderStore.nameOf(a.attendeeVendor), vendorOptions());
    setSelect($('attendee'), StaffStore.nameOf(a.attendee), staffOptions());
    setSelect($('motivationVendor'), TeacherVenderStore.nameOf(a.motivationVendor), vendorOptions());
    setSelect($('motivationStaff'), StaffStore.nameOf(a.motivationStaff), staffOptions());

    $('addMain').addEventListener('click', function () { makeRow('mainList', { vendor: '', staff: '' }); });
    $('addSub').addEventListener('click', function () { makeRow('subList', { vendor: '', staff: '' }); });

    $('saveBtn').addEventListener('click', function () {
      var mains = readRows('mainList');
      var subs = readRows('subList');
      var record = {
        classId: classId,
        mainCount: a.mainCount,
        subCount: a.subCount,
        mains: mains,
        subs: subs,
        attendeeVendor: TeacherVenderStore.codeOf(clean(ownText($('attendeeVendor')))),
        attendee: StaffStore.codeOf(clean(ownText($('attendee')))),
        motivationVendor: TeacherVenderStore.codeOf(clean(ownText($('motivationVendor')))),
        motivationStaff: StaffStore.codeOf(clean(ownText($('motivationStaff'))))
      };
      VenderAssignStore.upsert(record);
      location.href = 'class_vender_list.html';
    });
  }

  window.VenderAssignEditor = { init: init };
})();
