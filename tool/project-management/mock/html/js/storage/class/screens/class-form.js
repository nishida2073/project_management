(function () {
  function setSelect(el, value) {
    var v = value || '';
    el.setAttribute('data-value', v);
    el.innerHTML = (v ? esc(v) : '選択してください') + '<span class="caret">▾</span>';
  }
  function getSelect(el) {
    return ownText(el);
  }
  function setDate(el, value) {
    el.innerHTML = (value ? esc(value) : '') + '<span class="caret">▾</span>';
  }
  function getDate(el) {
    return ownText(el);
  }
  function checkRadio(name, value) {
    var r = document.querySelector('input[name="' + name + '"][value="' + value + '"]');
    if (r) r.checked = true;
  }
  function getRadio(name) {
    var r = document.querySelector('input[name="' + name + '"]:checked');
    return r ? r.value : '';
  }

  var lastCourse = '';
  function fillPlanFromCourse() {
    var cc = getSelect($('courseCode'));
    if (cc === lastCourse) return;
    lastCourse = cc;
    refreshDerived();
    if (!cc) return;
    var c = (CourseStore.map()[cc]) || {};
    $('mainTeachers').querySelector('input').value = c.mainTeachers === undefined ? '' : c.mainTeachers;
    $('subTeachers').querySelector('input').value = c.subTeachers === undefined ? '' : c.subTeachers;
  }
  document.addEventListener('click', function () { setTimeout(fillPlanFromCourse, 0); }, true);
  function refreshDerived() {
    var P = ClassStore.PROJECTS, C = ClassStore.COURSES;
    var pc = getSelect($('projectCode'));
    var p = P[pc];
    $('projectName').textContent = p ? p.name : '';
    $('projectSalesType').textContent = p ? SalesTypeStore.nameOf(p.sales) : '';
    $('projectSalesType').className = p ? 'tag ' + SalesTypeStore.colorOf(p.sales) : '';
    $('projectParticipationType').textContent = p ? ParticipationTypeStore.nameOf(p.part) : '';
    $('projectParticipationType').className = p ? 'tag ' + ParticipationTypeStore.colorOf(p.part) : '';

    var cc = getSelect($('courseCode'));
    var c = C[cc];
    $('courseName').textContent = c ? c.name : '';
    $('courseParticipationType').textContent = c ? ParticipationTypeStore.nameOf(c.part) : '';
    $('courseParticipationType').className = c ? 'tag ' + ParticipationTypeStore.colorOf(c.part) : '';
    $('courseDeliveryType').textContent = c ? DeliveryTypeStore.nameOf(c.delivery) : '';
    $('courseDeliveryType').className = c ? 'tag ' + DeliveryTypeStore.colorOf(c.delivery) : '';
    $('courseSchedule').textContent = c ? c.schedule : '';
    if ($('courseTeachers')) $('courseTeachers').textContent = c ? '講師 メイン' + (c.mainTeachers === undefined ? '-' : c.mainTeachers) + '人・サブ' + (c.subTeachers === undefined ? '-' : c.subTeachers) + '人' : '';
    if ($('courseRecommend')) $('courseRecommend').style.display = c ? '' : 'none';
  }

  function relatedBox() {
    return document.getElementById('relatedClasses');
  }

  function addRelatedChip(value) {
    var box = relatedBox();
    var chip = document.createElement('span');
    chip.className = 'chip tag-like blue';
    chip.appendChild(document.createTextNode(value + ' '));
    var x = document.createElement('x');
    x.textContent = '✕';
    x.addEventListener('click', function (e) { e.stopPropagation(); chip.remove(); });
    chip.appendChild(x);
    box.insertBefore(chip, box.querySelector('.chip-add'));
  }

  function addManagerChip(box, name) {
    var chip = document.createElement('span');
    chip.className = 'chip tag-like blue';
    chip.appendChild(document.createTextNode(name + ' '));
    var x = document.createElement('x');
    x.textContent = '✕';
    x.addEventListener('click', function (e) { e.stopPropagation(); chip.remove(); });
    chip.appendChild(x);
    box.insertBefore(chip, box.querySelector('.chip-add'));
  }

  function fillRelated(codes) {
    var box = relatedBox();
    box.querySelectorAll('.chip').forEach(function (c) { c.remove(); });
    sortCodes(codes || []).forEach(function (code) { addRelatedChip(code); });
  }

  function sortCodes(list) {
    return list.slice().sort(function (a, b) { return String(a).localeCompare(String(b), 'ja', { numeric: true }); });
  }

  function readRelated() {
    return sortCodes(Array.prototype.map.call(relatedBox().querySelectorAll('.chip'), function (c) {
      return (c.childNodes[0].textContent || '').trim();
    }));
  }

  function fill(r) {
    setSelect($('projectYear'), r.year);
    setSelect($('projectCode'), r.projectCode);
    setSelect($('courseYear'), r.courseYear);
    setSelect($('courseCode'), r.courseCode);
    setSelect($('version'), r.version || '1.0');
    checkRadio('taskType', r.taskType || '');
    var statusOff = r.status === '停止中';
    $('statusRow').setAttribute('data-on', '稼働中');
    $('statusRow').setAttribute('data-off', '停止中');
    setStatusOff(statusOff);
    $('statusLabel').textContent = statusOff ? '停止中' : '稼働中';
    $('lessonNo').textContent = r.lessonNo || '自動採番';
    setDate($('start'), r.start);
    setDate($('end'), r.end);
    checkRadio('deliveryType', r.delivery);
    $('people').querySelector('input').value = r.people || '';
    $('mainTeachers').querySelector('input').value = r.registMainTeachers !== undefined ? r.registMainTeachers : (r.mainTeachers || '');
    $('subTeachers').querySelector('input').value = r.registSubTeachers !== undefined ? r.registSubTeachers : (r.subTeachers || '');
    if ($('mainAdjusted')) $('mainAdjusted').textContent = '依頼後：' + (r.mainTeachers || '-') + '人';
    if ($('subAdjusted')) $('subAdjusted').textContent = '依頼後：' + (r.subTeachers || '-') + '人';
    lastCourse = getSelect($('courseCode'));
    var mbox = $('manager');
    var madd = mbox.querySelector('.chip-add');
    mbox.querySelectorAll('.chip').forEach(function (c) { c.remove(); });
    (r.managers || []).forEach(function (code) { addManagerChip(mbox, StaffStore.nameOf(code)); });
    checkRadio('locationType', r.locationType);
    setSelect($('locationName'), LocationStore.nameOf(r.locationName));
    $('memo').value = r.memo || '';
    fillRelated(r.related);
    refreshDerived();
  }

  function read() {
    return {
      year: getSelect($('projectYear')),
      projectCode: getSelect($('projectCode')),
      courseYear: getSelect($('courseYear')),
      courseCode: getSelect($('courseCode')),
      version: getSelect($('version')),
      taskType: getRadio('taskType'),
      start: getDate($('start')),
      end: getDate($('end')),
      delivery: getRadio('deliveryType'),
      people: $('people').querySelector('input').value.trim(),
      mainTeachers: $('mainTeachers').querySelector('input').value.trim(),
      registMainTeachers: $('mainTeachers').querySelector('input').value.trim(),
      subTeachers: $('subTeachers').querySelector('input').value.trim(),
      registSubTeachers: $('subTeachers').querySelector('input').value.trim(),
      managers: Array.prototype.map.call($('manager').querySelectorAll('.chip'), function (c) { return StaffStore.codeOf((c.childNodes[0].textContent || '').trim()); }).filter(Boolean),
      locationType: getRadio('locationType'),
      locationName: LocationStore.codeOf(getSelect($('locationName'))),
      memo: $('memo').value,
      status: readStatus(),
      related: readRelated()
    };
  }

  window.ClassForm = { fill: fill, read: read, refreshDerived: refreshDerived };
})();
