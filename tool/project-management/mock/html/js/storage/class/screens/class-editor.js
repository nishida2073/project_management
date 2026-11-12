(function () {
  function clean(s) {
    return s === '選択してください' ? '' : s;
  }

  function colorMap(items) {
    return items.reduce(function (m, it) { m[it.name] = it.color; return m; }, {});
  }

  function applyOptions() {
    var projects = ProjectStore.load();
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

    var courses = CourseStore.load();
    var cc = document.getElementById('courseCode');
    var cName = {}, cPart = {}, cDelivery = {}, cSchedule = {};
    courses.forEach(function (c) {
      cName[c.code] = c.name;
      cPart[c.code] = ParticipationTypeStore.nameOf(c.part);
      cDelivery[c.code] = DeliveryTypeStore.nameOf(c.delivery);
      cSchedule[c.code] = c.days + '日・' + c.min + '〜' + c.max + '名';
    });
    cc.setAttribute('data-options', courses.map(function (c) { return c.code; }).join(','));
    cc.setAttribute('data-map', JSON.stringify(cName));
    cc.setAttribute('data-map2', JSON.stringify(cPart));
    cc.setAttribute('data-map3', JSON.stringify(cDelivery));
    cc.setAttribute('data-map4', JSON.stringify(cSchedule));
    cc.setAttribute('data-class-map2', JSON.stringify(colorMap(ParticipationTypeStore.load())));
    cc.setAttribute('data-class-map3', JSON.stringify(colorMap(DeliveryTypeStore.load())));

    document.getElementById('manager').setAttribute('data-options', StaffStore.activeNames().join(','));
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
        alert('対象のクラスが見つかりません');
        location.href = 'class_list.html';
        return;
      }
      var c = ClassStore.COURSES[rec.courseCode];
      document.getElementById('subLine').textContent =
        rec.lessonNo + '　' + (c ? c.name : rec.courseCode) + 'の情報を編集します';
    } else {
      rec = {
        year: '2026年度', courseYear: '2026年度', version: '1.0', taskType: '', projectCode: '', courseCode: '', lessonNo: '',
        related: [], start: '', end: '', delivery: 'DL-01', people: '', manager: '',
        locationType: 'LT-01', locationName: '', memo: ''
      };
    }

    ClassForm.fill(rec);
    setupVersionOptions();

    if (!editing) {
      var startEl = document.getElementById('start');
      var endEl = document.getElementById('end');
      var courseEl = document.getElementById('courseCode');
      var endTouched = false;

      function textOf(el) {
        return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
          .map(function (n) { return n.textContent; }).join('').trim();
      }
      function fmt(d) {
        return d.getFullYear() + '/' + String(d.getMonth() + 1).padStart(2, '0') + '/' + String(d.getDate()).padStart(2, '0');
      }
      function setDefaultEnd() {
        if (endTouched) return;
        var s = textOf(startEl);
        var code = textOf(courseEl);
        var course = CourseStore.load().filter(function (c) { return c.code === code; })[0];
        if (!/^\d{4}\/\d{2}\/\d{2}$/.test(s) || !course || !course.days) return;
        var d = new Date(s.replace(/\//g, '-'));
        var remaining = Number(course.days) - 1;
        while (remaining > 0) {
          d.setDate(d.getDate() + 1);
          var dow = d.getDay();
          if (dow !== 0 && dow !== 6 && !HolidayStore.isHoliday(fmt(d))) remaining--;
        }
        endEl.innerHTML = fmt(d) + '<span class="caret">▾</span>';
      }

      endEl.addEventListener('click', function () { endTouched = true; }, true);
      new MutationObserver(setDefaultEnd).observe(startEl, { childList: true, characterData: true, subtree: true });
      new MutationObserver(setDefaultEnd).observe(courseEl, { attributes: true, attributeFilter: ['data-value'] });
      setDefaultEnd();
    }

    document.getElementById('saveBtn').addEventListener('click', function () {
      var v = ClassForm.read();
      v.year = clean(v.year);
      v.projectCode = clean(v.projectCode);
      v.courseCode = clean(v.courseCode);
      v.manager = clean(v.manager);
      if (!v.projectCode || !v.courseCode || !v.version || !v.taskType || !v.start || !v.end || !v.delivery || !v.locationType) {
        alert('必須項目を入力してください');
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
