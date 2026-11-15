(function () {
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }

  function sec(t) { return '<div class="form-section">' + esc(t) + '</div>'; }
  function empty() { return '<div class="form-field"></div>'; }
  function ro(label, text, full) {
    return '<div class="form-field' + (full ? ' full' : '') + '"><label>' + esc(label) + '</label>' +
      '<div class="form-value">' + esc(text || '-') + '</div></div>';
  }
  function roRaw(label, html, full) {
    return '<div class="form-field' + (full ? ' full' : '') + '"><label>' + esc(label) + '</label>' +
      '<div class="form-value">' + (html || '-') + '</div></div>';
  }
  function tagOf(text, color) {
    return '<span class="tag ' + esc(color || '') + '">' + esc(text) + '</span>';
  }
  function yearText(v) { return v ? String(v).replace('年度', '') + '年度' : '-'; }

  var id = new URLSearchParams(location.search).get('id');
  var list = ClassStore.load();
  var src = list.filter(function (r) { return r.id === id; })[0];
  if (!src) {
    MessageDialog.show('対象のクラスが見つかりません', function () { location.href = 'class_list.html'; });
    return;
  }

  var c = ClassStore.COURSES[src.courseCode] || {};
  var p = ClassStore.PROJECTS[src.projectCode] || {};
  $('subLine').textContent = (c.name || src.courseCode || '') + '　' + src.lessonNo + '　' + src.start + '〜' + src.end;
  $('cancelLink').href = 'class_modify.html?id=' + encodeURIComponent(src.id);

  function storeName(store, code) { return code && store ? (store.nameOf(code) || code) : ''; }
  function courseLabel(code) { return code ? (c.name ? c.name + '（' + code + '）' : code) : ''; }

  function sourceHtml() {
    var mgr = (src.managers || []).map(function (m) { return tagOf(StaffStore.nameOf(m), 'blue'); }).join(' ');
    var related = (src.related || []).map(function (r) { return tagOf(r, 'blue'); }).join(' ');
    var deliveryTag = src.delivery ? tagOf(DeliveryTypeStore.nameOf(src.delivery), DeliveryTypeStore.colorOf(src.delivery)) : '';
    var locTypeTag = src.locationType ? tagOf(LocationTypeStore.nameOf(src.locationType), LocationTypeStore.colorOf(src.locationType)) : '';
    var taskTag = src.taskType ? tagOf(TaskTypeStore.nameOf(src.taskType), TaskTypeStore.colorOf(src.taskType)) : '';
    return [
      sec('案件'),
      '<div class="form-field full"><div class="form-value">' + [
        '<span>' + esc(yearText(src.year)) + '</span>',
        '<span>' + esc(src.projectCode || '') + '</span>',
        p.name ? '<span>' + esc(p.name) + '</span>' : '',
        p.sales ? tagOf(SalesTypeStore.nameOf(p.sales), SalesTypeStore.colorOf(p.sales)) : '',
        p.part ? tagOf(ParticipationTypeStore.nameOf(p.part), ParticipationTypeStore.colorOf(p.part)) : ''
      ].filter(Boolean).join('') + '</div></div>',
      sec('コース'),
      '<div class="form-field full"><div class="form-value">' + [
        '<span>' + esc(src.courseCode || '') + '</span>',
        '<span>' + esc(c.name || '') + '</span>',
        c.part ? tagOf(ParticipationTypeStore.nameOf(c.part), ParticipationTypeStore.colorOf(c.part)) : '',
        '<span>' + esc('版' + (src.version || '-')) + '</span>',
        c.delivery ? '<span class="form-value-note">推奨：<span class="tag ' + esc(DeliveryTypeStore.colorOf(c.delivery)) + '">' + esc(DeliveryTypeStore.nameOf(c.delivery)) + '</span> ' + esc(c.schedule || '') + ' 講師 メイン' + (c.mainTeachers === undefined ? '-' : c.mainTeachers) + '人・サブ' + (c.subTeachers === undefined ? '-' : c.subTeachers) + '人</span>' : ''
      ].filter(Boolean).join('') + '</div></div>',
    ].join('');
  }
  $('copyItems').innerHTML = sourceHtml();

  function textOf(el) {
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
      .map(function (n) { return n.textContent; }).join('').trim();
  }

  function numberSelect(k, f, options, value, required) {
    return '<div class="form-field"><label>' + esc(f.label) + (required ? '<span class="req">必須</span>' : '') + '</label>' +
      '<div class="form-control number-select" data-k="' + k + '" data-f="' + f.key + '" data-options="' + esc(options) + '">' +
      '<input type="text" inputmode="numeric" value="' + esc(value) + '"><span class="caret">▾</span></div></div>';
  }

  function renderPerCopy() {
    var count = parseInt($('copyCount').value, 10);
    if (!count || count < 1 || count > 10) { $('perCopy').innerHTML = ''; return; }
    var types = LocationTypeStore.load();
    var byType = LocationStore.namesByType();
    var html = '';
    for (var k = 1; k <= count; k++) {
      var typeRadios = types.map(function (t) {
        return '<label class="radio-option"><input type="radio" name="locationType-' + k + '" value="' + esc(t.code) + '"' + (t.code === src.locationType ? ' checked' : '') + '><span class="radio-dot"></span><span class="tag ' + esc(t.color) + '">' + esc(t.name) + '</span></label>';
      }).join('');
      var initName = '';
      var initOptions = (byType[src.locationType] || []).join(',');
      html += sec('複製 ' + k) +
        '<div class="form-field"><label>開始日<span class="req">必須</span></label><div class="form-control js-date" data-k="' + k + '" data-f="start">' + esc(src.start) + '<span class="caret">▾</span></div></div>' +
        '<div class="form-field"><label>終了日<span class="req">必須</span></label><div class="form-control js-date" data-k="' + k + '" data-f="end">' + esc(src.end) + '<span class="caret">▾</span></div></div>' +
        numberSelect(k, { key: 'people', label: '受講人数' }, '10,15,20,24,30,35,40,50', '', false) + empty() +
        numberSelect(k, { key: 'mainTeachers', label: '予定講師数（メイン）' }, '0,1,2,3,4,5', src.mainTeachers == null ? '' : src.mainTeachers, true) +
        numberSelect(k, { key: 'subTeachers', label: '予定講師数（サブ）' }, '0,1,2,3,4,5', src.subTeachers == null ? '' : src.subTeachers, true) +
        '<div class="form-field full"><label>ロケーション区分<span class="req">必須</span></label><div class="radio-group" data-k="' + k + '">' + typeRadios + '</div></div>' +
        '<div class="form-field"><label>ロケーション名</label><div class="form-control js-select" data-k="' + k + '" data-f="locationName" data-value="' + esc(initName) + '" data-options="' + esc(initOptions) + '">' + esc(initName || '選択してください') + '<span class="caret">▾</span></div></div>';
    }
    $('perCopy').innerHTML = html;
    $('perCopy').querySelectorAll('.js-date').forEach(function (el) { window.bindDatePicker(el); });
    $('perCopy').querySelectorAll('.js-select').forEach(function (el) { window.bindJsSelect(el); });
    $('perCopy').querySelectorAll('.number-select').forEach(function (el) { window.bindNumberSelect(el); });
    for (var j = 1; j <= count; j++) {
      (function (kk) {
        document.querySelectorAll('input[name="locationType-' + kk + '"]').forEach(function (radio) {
          radio.addEventListener('change', function () {
            var target = document.querySelector('[data-k="' + kk + '"][data-f="locationName"]');
            var names = byType[radio.value] || [];
            if (target) window.jsSelectSetOptions(target, names);
          });
        });
      })(j);
    }
  }
  (function () {
    var sw = $('relateToSource');
    var label = sw.parentNode.querySelector('span');
    sw.addEventListener('click', function () {
      var off = sw.classList.toggle('off');
      label.textContent = off ? 'しない' : 'する';
    });
  })();
  $('copyCount').addEventListener('input', renderPerCopy);
  renderPerCopy();

  function fieldEl(k, f) { return document.querySelector('[data-k="' + k + '"][data-f="' + f + '"]'); }
  function dateVal(k, f) { var el = fieldEl(k, f); return el ? textOf(el) : ''; }
  function numVal(k, f) { var el = fieldEl(k, f); return el ? el.querySelector('input').value.trim() : ''; }
  function typeCode(k) {
    var r = document.querySelector('input[name="locationType-' + k + '"]:checked');
    return r ? r.value : '';
  }
  function locNameVal(k) {
    var el = fieldEl(k, 'locationName');
    return el ? (el.getAttribute('data-value') || '') : '';
  }

  $('copyBtn').addEventListener('click', function () {
    var count = parseInt($('copyCount').value, 10);
    if (!count || count < 1 || count > 10) {
      $('copyError').textContent = '複製するクラス数は1〜10で入力してください';
      return;
    }
    var missing = [];
    for (var k = 1; k <= count; k++) {
      if (!dateVal(k, 'start')) missing.push('複製 ' + k + ' の開始日');
      if (!dateVal(k, 'end')) missing.push('複製 ' + k + ' の終了日');
      if (!typeCode(k)) missing.push('複製 ' + k + ' のロケーション区分');
      if (numVal(k, 'mainTeachers') === '') missing.push('複製 ' + k + ' の予定講師数（メイン）');
      if (numVal(k, 'subTeachers') === '') missing.push('複製 ' + k + ' の予定講師数（サブ）');
    }
    if (missing.length) {
      MessageDialog.required(missing);
      return;
    }
    var relate = !$('relateToSource').classList.contains('off');
    var all = ClassStore.load();
    var created = [];
    for (var n = 1; n <= count; n++) {
      var copy = JSON.parse(JSON.stringify(src));
      copy.id = ClassStore.nextId(all);
      copy.lessonNo = ClassStore.nextLessonNo(all, src.courseCode);
      copy.related = (src.related || []).slice();
      if (relate) {
        created.forEach(function (prev) {
          prev.related = prev.related || [];
          if (copy.lessonNo && prev.related.indexOf(copy.lessonNo) === -1) prev.related.push(copy.lessonNo);
          if (prev.lessonNo && copy.related.indexOf(prev.lessonNo) === -1) copy.related.push(prev.lessonNo);
        });
        if (src.lessonNo && copy.related.indexOf(src.lessonNo) === -1) copy.related.push(src.lessonNo);
        var srcInAll = all.filter(function (r) { return r.id === src.id; })[0];
        if (srcInAll) {
          srcInAll.related = srcInAll.related || [];
          if (copy.lessonNo && srcInAll.related.indexOf(copy.lessonNo) === -1) srcInAll.related.push(copy.lessonNo);
        }
      }
      copy.status = '稼働中';
      copy.memo = '';
      copy.start = dateVal(n, 'start');
      copy.end = dateVal(n, 'end');
      copy.people = numVal(n, 'people');
      copy.mainTeachers = numVal(n, 'mainTeachers');
      copy.subTeachers = numVal(n, 'subTeachers');
      copy.registMainTeachers = copy.mainTeachers;
      copy.registSubTeachers = copy.subTeachers;
      copy.locationType = typeCode(n);
      copy.locationName = LocationStore.codeOf(locNameVal(n));
      all.push(copy);
      created.push(copy);
    }
    ClassStore.save(all);
    location.href = 'class_list.html';
  });
})();
