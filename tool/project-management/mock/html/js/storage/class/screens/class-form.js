(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }
  function ownText(el) {
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
      .map(function (n) { return n.textContent; }).join('').trim();
  }
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
  }

  function fillRelated(codes) {
    var list = document.querySelector('.related-class-list');
    Array.prototype.slice.call(list.querySelectorAll('.sub-row')).forEach(function (row) { row.remove(); });
    var items = codes && codes.length ? codes : [''];
    items.forEach(function (code) {
      var row = document.createElement('div');
      row.className = 'sub-row';
      row.innerHTML =
        '<div class="form-control number-select" data-options="002,003,004,005">' +
        '<input type="text" placeholder="例）002" value="' + esc(code) + '">' +
        '<span class="caret">▾</span></div>' +
        '<div class="sub-remove">✕</div>';
      list.appendChild(row);
    });
  }

  function readRelated() {
    return Array.prototype.map.call(document.querySelectorAll('.related-class-list .sub-row input'), function (i) {
      return i.value.trim();
    }).filter(Boolean);
  }

  function fill(r) {
    setSelect($('projectYear'), r.year);
    setSelect($('projectCode'), r.projectCode);
    setSelect($('courseYear'), r.courseYear);
    setSelect($('courseCode'), r.courseCode);
    setSelect($('version'), r.version || '1.0');
    $('lessonNo').textContent = r.lessonNo || '自動採番';
    setDate($('start'), r.start);
    setDate($('end'), r.end);
    checkRadio('deliveryType', r.delivery);
    $('people').querySelector('input').value = r.people || '';
    setSelect($('manager'), StaffStore.nameOf(r.manager));
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
      start: getDate($('start')),
      end: getDate($('end')),
      delivery: getRadio('deliveryType'),
      people: $('people').querySelector('input').value.trim(),
      manager: StaffStore.codeOf(getSelect($('manager'))),
      locationType: getRadio('locationType'),
      locationName: LocationStore.codeOf(getSelect($('locationName'))),
      memo: $('memo').value,
      related: readRelated()
    };
  }

  window.ClassForm = { fill: fill, read: read, refreshDerived: refreshDerived };
})();
