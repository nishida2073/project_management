(function () {
var ClassForm = (function () {
  function setDate(el, value) {
    el.innerHTML = (value ? esc(value) : '') + '<span class="caret">▾</span>';
  }
  function getDate(el) {
    return ownText(el);
  }
  function setTime(el, value) {
    el.setAttribute('data-value', value || '');
    el.innerHTML = (value ? esc(value) : '選択してください') + '<span class="caret">▾</span>';
  }
  function getTime(el) {
    return placeholderToEmpty(ownText(el));
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
    $('specialTeachers').querySelector('input').value = c.specialTeachers === undefined ? '' : c.specialTeachers;
  }
  document.addEventListener('click', function () { setTimeout(fillPlanFromCourse, 0); }, true);
  function refreshDays() {
    $('classDays').textContent = classDays({ start: getDate($('start')), end: getDate($('end')) });
  }
  function renderCustomAttributes() {
    CustomAttributeFields.render($('customAttributes'), 'class');
  }
  function readCustomAttributes() {
    return CustomAttributeFields.read($('customAttributes'));
  }
  function fillCustomAttributes(attrs) {
    CustomAttributeFields.fill($('customAttributes'), attrs);
  }
  function refreshDerived() {
    refreshDays();
    var P = ClassStore.PROJECTS, C = ClassStore.COURSES;
    var pc = getSelect($('projectCode'));
    var p = P[pc];
    $('projectName').textContent = p ? p.name : '';
    $('projectSalesType').textContent = p ? SalesTypeStore.nameOf(p.sales) : '';
    $('projectSalesType').className = p ? 'tag sales-type-tag ' + SalesTypeStore.colorOf(p.sales) : 'tag';
    $('projectParticipationType').textContent = p ? ParticipationTypeStore.nameOf(p.part) : '';
    $('projectParticipationType').className = p ? 'tag participation-type-tag ' + ParticipationTypeStore.colorOf(p.part) : 'tag';

    var cc = getSelect($('courseCode'));
    var c = C[cc];
    $('courseName').textContent = c ? c.name : '';
    $('courseParticipationType').textContent = c ? ParticipationTypeStore.nameOf(c.part) : '';
    $('courseParticipationType').className = c ? 'tag participation-type-tag ' + ParticipationTypeStore.colorOf(c.part) : 'tag';
    $('courseDeliveryType').textContent = c ? DeliveryTypeStore.nameOf(c.delivery) : '';
    $('courseDeliveryType').className = c ? 'tag delivery-type-tag ' + DeliveryTypeStore.colorOf(c.delivery) : 'tag';
    $('courseSchedule').textContent = c ? c.schedule : '';
    if ($('courseTeachers')) $('courseTeachers').textContent = c ? '講師 メイン' + (c.mainTeachers === undefined ? '-' : c.mainTeachers) + '人・サブ' + (c.subTeachers === undefined ? '-' : c.subTeachers) + '人' + '・特別' + (c.specialTeachers === undefined ? '-' : c.specialTeachers) + '人' : '';
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
    checkRadio('classType', r.classType || '');
    checkRadio('taskType', r.taskType || '');
    var statusOff = r.status === OperatingStatusStore.nameOf('STOPPED');
    $('statusRow').setAttribute('data-on', OperatingStatusStore.nameOf('ACTIVE'));
    $('statusRow').setAttribute('data-off', OperatingStatusStore.nameOf('STOPPED'));
    setStatusOff(statusOff);
    $('statusLabel').textContent = statusOff ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE');
    $('lessonNo').textContent = r.lessonNo || '自動採番';
    $('classId').textContent = r.lessonNo ? ClassStore.classIdOf(r) : '自動採番';
    setDate($('start'), r.start);
    setDate($('end'), r.end);
    setTime($('startTime'), r.startTime);
    setTime($('endTime'), r.endTime);
    checkRadio('deliveryType', r.delivery);
    $('people').querySelector('input').value = r.people || '';
    $('surveyPin').textContent = r.lessonNo ? ClassStore.surveyPinOf(r) : '自動採番';
    $('testPin').textContent = r.lessonNo ? ClassStore.testPinOf(r) : '自動採番';
    $('mainTeachers').querySelector('input').value = r.registMainTeachers !== undefined ? r.registMainTeachers : (r.mainTeachers || '');
    $('subTeachers').querySelector('input').value = r.registSubTeachers !== undefined ? r.registSubTeachers : (r.subTeachers || '');
    $('specialTeachers').querySelector('input').value = r.registSpecialTeachers !== undefined ? r.registSpecialTeachers : (r.specialTeachers || '');
    $('specialMemo').value = r.specialMemo || '';
    if ($('mainAdjusted')) $('mainAdjusted').textContent = SlotStatusStore.nameOf('REQUESTED') + '：' + (r.mainTeachers || '-') + '人';
    if ($('subAdjusted')) $('subAdjusted').textContent = SlotStatusStore.nameOf('REQUESTED') + '：' + (r.subTeachers || '-') + '人';
    lastCourse = getSelect($('courseCode'));
    var mbox = $('manager');
    var madd = mbox.querySelector('.chip-add');
    mbox.querySelectorAll('.chip').forEach(function (c) { c.remove(); });
    (r.managers || []).forEach(function (code) { addManagerChip(mbox, StaffStore.nameOf(code)); });
    checkRadio('locationType', r.locationType);
    setSelect($('locationName'), r.locationName || '');
    $('practiceRoom').value = r.practiceRoom || '';
    setSelect($('sharedPcGroup'), SharedPcGroupStore.nameOf(r.sharedPcGroup));
    $('memo').value = r.memo || '';
    fillCustomAttributes(r.attributes);
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
      classType: getRadio('classType'),
      taskType: getRadio('taskType'),
      start: getDate($('start')),
      end: getDate($('end')),
      startTime: getTime($('startTime')),
      endTime: getTime($('endTime')),
      delivery: getRadio('deliveryType'),
      people: $('people').querySelector('input').value.trim(),
      mainTeachers: $('mainTeachers').querySelector('input').value.trim(),
      registMainTeachers: $('mainTeachers').querySelector('input').value.trim(),
      subTeachers: $('subTeachers').querySelector('input').value.trim(),
      registSubTeachers: $('subTeachers').querySelector('input').value.trim(),
      specialTeachers: $('specialTeachers').querySelector('input').value.trim() || '0',
      registSpecialTeachers: $('specialTeachers').querySelector('input').value.trim() || '0',
      specialMemo: $('specialMemo').value,
      managers: Array.prototype.map.call($('manager').querySelectorAll('.chip'), function (c) { return StaffStore.codeOf((c.childNodes[0].textContent || '').trim()); }).filter(Boolean),
      locationType: getRadio('locationType'),
      locationName: placeholderToEmpty(getSelect($('locationName'))),
      practiceRoom: $('practiceRoom').value.trim(),
      sharedPcGroup: SharedPcGroupStore.codeOf(getSelect($('sharedPcGroup'))),
      memo: $('memo').value,
      attributes: readCustomAttributes(),
      status: readStatus(),
      related: readRelated()
    };
  }

  return { fill: fill, read: read, refreshDerived: refreshDerived, refreshDays: refreshDays, renderCustomAttributes: renderCustomAttributes };

})();

  function colorMap(items) {
    return items.reduce(function (m, it) { m[it.name] = it.color; return m; }, {});
  }

  function setYearMap(selectId, list) {
    var map = { "2024": [], "2025": [], "2026": [], "2027": [] };
    list.forEach(function (x) { if (!map[x.year]) map[x.year] = []; map[x.year].push(x.code); });
    document.getElementById(selectId).setAttribute("data-options-map", JSON.stringify(map));
  }

  function applyOptions() {
    var projects = ProjectStore.load().filter(function (x) { return x.status !== OperatingStatusStore.nameOf('STOPPED'); });
    var pc = document.getElementById('projectCode');
    var pName = {}, pSales = {}, pPart = {};
    projects.forEach(function (p) {
      pName[p.code] = p.name;
      pSales[p.code] = SalesTypeStore.nameOf(p.sales);
      pPart[p.code] = ParticipationTypeStore.nameOf(p.part);
    });
    pc.setAttribute('data-options', projects.map(function (p) { return p.code; }).join(','));
    pc.setAttribute('data-map', JSON.stringify(pName));
    pc.setAttribute('data-map2', JSON.stringify(pSales));
    pc.setAttribute('data-map3', JSON.stringify(pPart));
    pc.setAttribute('data-class-map2', JSON.stringify(colorMap(SalesTypeStore.load())));
    pc.setAttribute('data-class-map3', JSON.stringify(colorMap(ParticipationTypeStore.load())));

    var courses = CourseStore.load().filter(function (x) { return x.status !== OperatingStatusStore.nameOf('STOPPED'); });
    var cc = document.getElementById('courseCode');
    var cName = {}, cPart = {}, cDelivery = {}, cSchedule = {};
    courses.forEach(function (c) {
      cName[c.code] = c.name;
      cPart[c.code] = ParticipationTypeStore.nameOf(c.part);
      cDelivery[c.code] = DeliveryTypeStore.nameOf(c.delivery);
      cSchedule[c.code] = c.days + '日・' + c.min + '〜' + c.max + '人';
    });
    cc.setAttribute('data-options', courses.map(function (c) { return c.code; }).join(','));
    setYearMap("projectYear", projects);
    setYearMap("courseYear", courses);
    cc.setAttribute('data-map', JSON.stringify(cName));
    cc.setAttribute('data-map2', JSON.stringify(cPart));
    cc.setAttribute('data-map3', JSON.stringify(cDelivery));
    cc.setAttribute('data-map4', JSON.stringify(cSchedule));
    cc.setAttribute('data-class-map2', JSON.stringify(colorMap(ParticipationTypeStore.load())));
    cc.setAttribute('data-class-map3', JSON.stringify(colorMap(DeliveryTypeStore.load())));

    document.getElementById('manager').setAttribute('data-options', StaffStore.candidates({
      roles: ['クラス'], jobTypes: ['管理']
    }).join(','));
    var locGroup = document.querySelector('.radio-group[data-target="#locationName"]');
    var byType = LocationStore.namesByType();
    LocationTypeStore.load().forEach(function (t) { if (!byType[t.code]) byType[t.code] = []; });
    locGroup.setAttribute('data-options-map', JSON.stringify(byType));
    document.getElementById('locationName').setAttribute('data-options', Object.keys(byType).reduce(function (a, k) { return a.concat(byType[k]); }, []).join(','));

  }
  function renderRadios(group, name, items) {
    group.innerHTML = items.map(function (it) {
      return '<label class="radio-option"><input type="radio" name="' + name + '" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + tagClassOf(name) + ' ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
  }

  function setupVersionOptions() {
    var courseEl = document.getElementById('courseCode');
    var versionEl = document.getElementById('version');
    function refresh() {
      var code = courseEl.getAttribute('data-value') || '';
      var course = CourseStore.load().filter(function (c) { return c.code === code; })[0];
      var subject = course ? SubjectStore.find(course.subject) : null;
      var versions = subject && subject.versions ? subject.versions : [];
      versionEl.setAttribute('data-options', versions.join(','));
      var current = versionEl.getAttribute('data-value') || '';
      if (current && versions.indexOf(current) === -1) {
        versionEl.setAttribute('data-value', '');
        versionEl.innerHTML = '選択してください<span class="caret">▾</span>';
      }
    }
    new MutationObserver(refresh).observe(courseEl, { attributes: true, attributeFilter: ['data-value'] });
    refresh();
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    ClassForm.renderCustomAttributes();
    new MutationObserver(ClassForm.refreshDays).observe($('start'), { childList: true, subtree: true, characterData: true });
    new MutationObserver(ClassForm.refreshDays).observe($('end'), { childList: true, subtree: true, characterData: true });
    renderRadios(document.querySelector('.radio-group[data-target="#locationName"]'), 'locationType', LocationTypeStore.load());
    document.getElementById('sharedPcGroup').setAttribute('data-options', SharedPcGroupStore.names().join(','));
    var deliveryGroup = document.querySelector('[data-master-radio="DeliveryTypeStore"]');
    renderRadios(deliveryGroup, 'deliveryType', DeliveryTypeStore.load());
    deliveryGroup.setAttribute('data-generated', '1');
    renderRadios(document.getElementById('classTypeGroup'), 'classType', ClassTypeStore.load());
    renderRadios(document.getElementById('taskTypeGroup'), 'taskType', TaskTypeStore.load());
    applyOptions();
    var list = ClassStore.load();
    var rec;
    var id = new URLSearchParams(location.search).get('id');

    if (editing) {
      list.forEach(function (r) { if (r.id === id) rec = r; });
      if (!rec) {
        MessageDialog.show('対象のクラスが見つかりません', function () { location.href = 'class_list.html'; });
        return;
      }
      var c = ClassStore.COURSES[rec.courseCode];
    } else {
      var fromId = new URLSearchParams(location.search).get('from');
      var fromRec = fromId ? list.filter(function (r) { return r.id === fromId; })[0] : null;
      if (fromRec) {
        var cancelEl = document.getElementById('cancelLink');
        if (cancelEl) cancelEl.href = 'class_modify.html?id=' + encodeURIComponent(fromRec.id);
      }
      rec = fromRec ? Object.assign(JSON.parse(JSON.stringify(fromRec)), { id: '', lessonNo: '', memo: '', status: OperatingStatusStore.nameOf('ACTIVE') }) : {
        year: '2026', courseYear: '2026', version: '1.0', classType: '', taskType: '', projectCode: '', courseCode: '', lessonNo: '',
        related: [], start: '', end: '', delivery: '', people: '', managers: [],
        locationType: '', locationName: '', memo: '', status: OperatingStatusStore.nameOf('STOPPED')
      };
    }

    if (editing) {
      var copyBtn = document.getElementById('copyBtn');
      if (copyBtn) copyBtn.addEventListener('click', function () {
        location.href = 'class_copy.html?id=' + encodeURIComponent(rec.id);
      });
      var simpleCopyBtn = document.getElementById('simpleCopyBtn');
      if (simpleCopyBtn) simpleCopyBtn.addEventListener('click', function () {
        location.href = 'class_regist.html?from=' + encodeURIComponent(rec.id);
      });
    }

    ClassForm.fill(rec);
    setupVersionOptions();

    function relatedOptions() {
      var code = document.getElementById('courseCode').getAttribute('data-value') || '';
      var selfId = editing ? rec.id : '';
      return ClassStore.load().filter(function (c) {
        return c.courseCode === code && c.id !== selfId && c.lessonNo;
      }).map(function (c) { return c.lessonNo; });
    }
    function refreshRelatedOptions(removeInvalid) {
      var box = document.getElementById('relatedClasses');
      if (!box) return;
      var opts = relatedOptions();
      box.setAttribute('data-options', opts.join(','));
      if (!removeInvalid) return;
      box.querySelectorAll('.chip').forEach(function (chip) {
        var v = (chip.childNodes[0].textContent || '').trim();
        if (opts.indexOf(v) === -1) chip.remove();
      });
    }
    refreshRelatedOptions(false);
    new MutationObserver(function () { refreshRelatedOptions(true); })
      .observe(document.getElementById('courseCode'), { attributes: true, attributeFilter: ['data-value'] });

    {
      var startEl = document.getElementById('start');
      var endEl = document.getElementById('end');
      var courseEl = document.getElementById('courseCode');
      var endTouched = false;

      function setDefaultEnd() {
        if (endTouched) return;
        var code = courseEl.getAttribute('data-value') || '';
        var course = CourseStore.load().filter(function (c) { return c.code === code; })[0];
        var out = calcEndDate(ownText(startEl), course ? course.days : null);
        if (out) endEl.innerHTML = out + '<span class="caret">▾</span>';
      }

      endEl.addEventListener('click', function () { endTouched = true; }, true);
      new MutationObserver(setDefaultEnd).observe(startEl, { childList: true, characterData: true, subtree: true });
      new MutationObserver(setDefaultEnd).observe(courseEl, { attributes: true, attributeFilter: ['data-value'] });
      if (!editing) setDefaultEnd();
    }

    {
      var startTimeEl = document.getElementById('startTime');
      var endTimeEl = document.getElementById('endTime');
      var courseTimeEl = document.getElementById('courseCode');
      var endTimeTouched = false;
      var timeTouched = false;

      function setDefaultEndTime() {
        if (endTimeTouched || !timeTouched) return;
        var start = placeholderToEmpty(ownText(startTimeEl));
        var code = courseTimeEl.getAttribute('data-value') || '';
        var course = CourseStore.load().filter(function (c) { return c.code === code; })[0];
        if (!start || !course || !course.duration) return;
        var end = TimeUtil.toMinutes(start) + Number(course.duration) + Number(course.breakTime || 0);
        if (end > 23 * 60 + 30) return;
        var t = TimeUtil.toTime(end);
        endTimeEl.setAttribute('data-value', t);
        endTimeEl.innerHTML = t + '<span class="caret">▾</span>';
      }

      document.addEventListener('click', function (e) {
        if (e.target.closest && e.target.closest('#startTime, #courseCode')) timeTouched = true;
      }, true);
      endTimeEl.addEventListener('click', function () { endTimeTouched = true; }, true);
      new MutationObserver(setDefaultEndTime).observe(startTimeEl, { attributes: true, attributeFilter: ['data-value'] });
      new MutationObserver(setDefaultEndTime).observe(courseTimeEl, { attributes: true, attributeFilter: ['data-value'] });
    }

    document.getElementById('saveBtn').addEventListener('click', function () {
      var v = ClassForm.read();
      v.year = placeholderToEmpty(v.year);
      v.projectCode = placeholderToEmpty(v.projectCode);
      v.courseCode = placeholderToEmpty(v.courseCode);
      v.version = placeholderToEmpty(v.version);
      v.courseYear = placeholderToEmpty(v.courseYear);
      var missing = [];
        if (!v.courseYear) missing.push('年度');
        if (!v.courseCode) missing.push('コースコード');
        if (!v.version) missing.push('版');
        if (!v.start) missing.push('開始日');
        if (!v.end) missing.push('終了日');
        if (!v.delivery) missing.push('実施形態');
        if (!v.classType) missing.push('クラス区分');
        if (!v.locationType) missing.push('ロケーション区分');
        if (v.mainTeachers === '') missing.push('予定講師数（メイン）');
        if (v.subTeachers === '') missing.push('予定講師数（サブ）');
        if (!v.taskType) missing.push('タスク区分');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (v.startTime && v.endTime && v.endTime <= v.startTime) {
        MessageDialog.show('終了時刻は開始時刻より後にしてください');
        return;
      }
      if (editing) {
        Object.keys(v).forEach(function (k) { rec[k] = v[k]; });
      } else {
        list.push(Object.assign({
          id: ClassStore.nextId(list),
          lessonNo: ClassStore.nextLessonNo(list, v.courseCode)
        }, v));
      }
      ClassStore.save(list);
      location.href = 'class_list.html';
    });
  }

  window.ClassEditor = { init: init };
})();
