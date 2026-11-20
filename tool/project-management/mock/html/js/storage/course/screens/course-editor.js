(function () {
  function getSelect(el) {
    var v = ownText(el);
    return v === '選択してください' ? '' : v;
  }
  function monthInputs() {
    return Array.prototype.slice.call(document.querySelectorAll('.month-grid input'));
  }

  function renderGroup(name, items) {
    var group = document.querySelector('[data-radio-name="' + name + '"]');
    group.innerHTML = items.map(function (it) {
      return '<label class="radio-option"><input type="radio" name="' + name + '" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + tagClassOf(name) + ' ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
    group.setAttribute('data-generated', '1');
  }

  function refreshSubject() {
    var s = SubjectStore.find(SubjectStore.codeOf(getSelect($('subjectSelect'))));
    $('subjectCode').textContent = s ? s.code : '';
    $('subjectType').textContent = s ? SubjectTypeStore.nameOf(s.type) : '';
    $('subjectType').className = 'tag ' + (s ? SubjectTypeStore.colorOf(s.type) : '');
  }

  function refreshAnnual() {
    var total = monthInputs().reduce(function (a, i) { return a + (parseInt(i.value, 10) || 0); }, 0);
    $('annualClassCount').textContent = total + 'クラス';
  }

  var nameEdited = false;
  var isEditing = false;

  function autoName() {
    var p = document.querySelector('input[name="participationType"]:checked');
    var part = p ? ParticipationTypeStore.nameOf(p.value) : '';
    var subject = getSelect($('subjectSelect'));
    if (!isEditing) {
      var subjectCode = SubjectStore.codeOf(subject);
      var suffix = part === ParticipationTypeStore.nameOf('PT-01') ? 'B' : (part === ParticipationTypeStore.nameOf('PT-02') ? 'A' : '');
      $('courseCode').value = (subjectCode && suffix) ? (subjectCode + suffix) : '';
    }
    if (nameEdited) return;
    $('courseName').value = (part && subject) ? (part + '_' + subject) : '';
  }

  function fill(rec, editing) {
    setSelect($('subjectSelect'), SubjectStore.nameOf(rec.subject));
    setSelect($('courseYear'), rec.year);
    $('courseCode').value = rec.code || '';
    $('courseCode').disabled = true;
    $('courseCode').classList.add('readonly');
    checkRadio('participationType', rec.part || '');
    $('courseName').value = rec.name || '';
    checkRadio('deliveryType', rec.delivery || '');
    $('days').querySelector('input').value = rec.days === undefined ? '' : rec.days;
    $('minPeople').querySelector('input').value = rec.min === undefined ? '' : rec.min;
    $('maxPeople').querySelector('input').value = rec.max === undefined ? '' : rec.max;
    $('mainTeachers').querySelector('input').value = rec.mainTeachers === undefined ? '' : rec.mainTeachers;
    $('subTeachers').querySelector('input').value = rec.subTeachers === undefined ? '' : rec.subTeachers;
    $('specialTeachers').querySelector('input').value = rec.specialTeachers === undefined ? '' : rec.specialTeachers;
    var inputs = monthInputs();
    inputs.forEach(function (i, idx) { i.value = (rec.monthly && rec.monthly[idx]) || 0; });
    $('memo').value = rec.memo || '';
    var row = $('statusRow');
    row.setAttribute('data-on', OperatingStatusStore.nameOf('ACTIVE'));
    row.setAttribute('data-off', OperatingStatusStore.nameOf('STOPPED'));
    var off = rec.status === OperatingStatusStore.nameOf('STOPPED');
    setStatusOff(off);
    $('statusLabel').textContent = off ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE');
    refreshSubject();
    refreshAnnual();
  }

  function read() {
    var off = (readStatus() === OperatingStatusStore.nameOf('STOPPED'));
    return {
      year: getSelect($('courseYear')),
      code: $('courseCode').value.trim(),
      subject: SubjectStore.codeOf(getSelect($('subjectSelect'))),
      part: getRadio('participationType'),
      name: $('courseName').value.trim(),
      delivery: getRadio('deliveryType'),
      days: $('days').querySelector('input').value.trim(),
      min: $('minPeople').querySelector('input').value.trim(),
      max: $('maxPeople').querySelector('input').value.trim(),
      mainTeachers: $('mainTeachers').querySelector('input').value.trim(),
      subTeachers: $('subTeachers').querySelector('input').value.trim(),
      specialTeachers: $('specialTeachers').querySelector('input').value.trim(),
      monthly: monthInputs().map(function (i) { return parseInt(i.value, 10) || 0; }),
      memo: $('memo').value,
      status: off ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE')
    };
  }

  function applyOptions() {
    $('subjectSelect').setAttribute('data-options', SubjectStore.activeNames().join(','));
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    applyOptions();
    isEditing = editing;
    renderGroup('participationType', ParticipationTypeStore.load());
    if (editing) {
      document.querySelector('input[name="participationType"]').closest('.radio-group').style.opacity = '0.6';
      document.querySelectorAll('input[name="participationType"]').forEach(function (r) { r.disabled = true; });
    }
    renderGroup('deliveryType', DeliveryTypeStore.load());
    var list = CourseStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    if (editing) {
      list.forEach(function (c, i) { if (c.code === id) idx = i; });
      if (idx < 0) {
        MessageDialog.show('対象のコースが見つかりません', function () { location.href = 'course_list.html'; });
        return;
      }
      rec = list[idx];
    } else {
      rec = { year: '2026', subject: '', part: '', name: '', delivery: '', days: '', min: '', max: '', monthly: [], status: OperatingStatusStore.nameOf('ACTIVE'), code: '' };
    }

    fill(rec, editing);

    $('courseName').addEventListener('input', function () { nameEdited = true; });
    document.querySelectorAll('input[name="participationType"]').forEach(function (r) { r.addEventListener('change', autoName); });
    new MutationObserver(function () { refreshSubject(); autoName(); }).observe($('subjectSelect'), { attributes: true, attributeFilter: ['data-value'] });
    document.querySelector('.month-grid').addEventListener('input', refreshAnnual);
    document.addEventListener('click', function () { setTimeout(refreshAnnual, 0); }, true);

    $('saveBtn').addEventListener('click', function () {
      var v = read();
      var missing = [];
        if (!v.code) missing.push('コースコード');
        if (!v.year) missing.push('年度');
        if (!v.subject) missing.push('科目名');
        if (!v.part) missing.push('参加区分');
        if (!v.name) missing.push('コース名');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (!editing && list.some(function (c) { return c.code === v.code; })) {
        MessageDialog.show('同じコースコードが既に登録されています');
        return;
      }
      var item = {
        code: v.code, year: v.year, subject: v.subject, part: v.part,
        name: v.name, delivery: v.delivery, days: v.days === '' ? '' : parseInt(v.days, 10), min: v.min === '' ? '' : parseInt(v.min, 10),
        max: v.max === '' ? '' : parseInt(v.max, 10), status: v.status, monthly: v.monthly,
        mainTeachers: v.mainTeachers === '' ? '' : parseInt(v.mainTeachers, 10),
        subTeachers: v.subTeachers === '' ? '' : parseInt(v.subTeachers, 10),
        specialTeachers: v.specialTeachers === '' ? '' : parseInt(v.specialTeachers, 10),
        actual: editing ? list[idx].actual : 0,
        memo: v.memo
      };
      if (editing) {
        list[idx] = item;
      } else {
        list.push(item);
      }
      CourseStore.save(list);
      location.href = 'course_list.html';
    });
  }

  window.CourseEditor = { init: init };
})();

