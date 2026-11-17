(function () {

  function colorMap(items) {
    return items.reduce(function (m, it) { m[it.name] = it.color; return m; }, {});
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
    locGroup.setAttribute('data-options-map', JSON.stringify(byType));
    document.getElementById('locationName').setAttribute('data-options', Object.keys(byType).reduce(function (a, k) { return a.concat(byType[k]); }, []).join(','));

  }
  function renderRadios(group, name, items) {
    group.innerHTML = items.map(function (it) {
      return '<label class="radio-option"><input type="radio" name="' + name + '" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + it.color + '">' + it.name + '</span></label>';
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
    renderRadios(document.querySelector('.radio-group[data-target="#locationName"]'), 'locationType', LocationTypeStore.load());
    renderRadios(document.querySelector('input[name="deliveryType"]').closest('.radio-group'), 'deliveryType', DeliveryTypeStore.load());
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
        year: '2026', courseYear: '2026', version: '1.0', taskType: '', projectCode: '', courseCode: '', lessonNo: '',
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
        if (!v.taskType) missing.push('タスク区分');
        if (!v.start) missing.push('開始日');
        if (!v.end) missing.push('終了日');
        if (!v.delivery) missing.push('実施形態');
        if (!v.locationType) missing.push('ロケーション区分');
        if (v.mainTeachers === '') missing.push('予定講師数（メイン）');
        if (v.subTeachers === '') missing.push('予定講師数（サブ）');
      if (missing.length) {
        MessageDialog.required(missing);
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
