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

  function chooseWithdraw(names) {
    return new Promise(function (resolve) {
      var overlay = document.createElement('div');
      overlay.className = 'overlay';
      overlay.innerHTML =
        '<div class="input-dialog">' +
          '<div class="input-dialog-title">依頼を取り下げる</div>' +
          '<label class="input-dialog-label">講師ベンダー名</label>' +
          '<div class="form-control js-select" data-options="' + esc(names.join(',')) + '" data-value="' + esc(names.length === 1 ? names[0] : '') + '">' +
            esc(names.length === 1 ? names[0] : '選択してください') + '<span class="caret">▾</span></div>' +
          '<div class="input-dialog-error"></div>' +
          '<div class="input-dialog-actions">' +
            '<div class="search-btn wd-cancel">キャンセル</div>' +
            '<div class="btn primary wd-ok">取り下げる</div>' +
          '</div>' +
        '</div>';
      document.body.appendChild(overlay);
      var sel = overlay.querySelector('.js-select');
      var errorEl = overlay.querySelector('.input-dialog-error');
      window.bindJsSelect(sel);

      function close(value) {
        document.removeEventListener('keydown', onKey);
        overlay.remove();
        resolve(value);
      }
      function onKey(e) { if (e.key === 'Escape') close(null); }

      overlay.querySelector('.wd-ok').addEventListener('click', function () {
        var name = sel.getAttribute('data-value') || '';
        if (!name || names.indexOf(name) === -1) {
          errorEl.textContent = '講師ベンダー名を選択してください';
          return;
        }
        close(name);
      });
      overlay.querySelector('.wd-cancel').addEventListener('click', function () { close(null); });
      overlay.addEventListener('click', function (e) { if (e.target === overlay) close(null); });
      document.addEventListener('keydown', onKey);
    });
  }

  function vendorOptions() { return TeacherVenderStore.activeNames(); }
  function staffOptions() { return StaffStore.activeNames(); }

  function makeRow(listId, data) {
    var row = document.createElement('div');
    row.className = 'sub-grid sub-row';
    var vendorCell = data.locked
      ? '<div class="form-control readonly vendor-fixed" data-code="' + esc(data.vendor) + '">' + esc(TeacherVenderStore.nameOf(data.vendor) || '-') + '</div>'
      : '<div class="form-control js-select" data-options="' + esc(vendorOptions().join(',')) + '">' + esc(TeacherVenderStore.nameOf(data.vendor) || '選択してください') + '<span class="caret">▾</span></div>';
    row.innerHTML =
      vendorCell +
      '<input type="text" class="form-control" placeholder="講師名" value="' + esc(data.staff || '') + '">' +
      (data.locked ? '' : '<div class="sub-remove">✕</div>') +
      '<span class="tag sub-status"></span>';
    if (!data.locked) row.querySelector('.sub-remove').addEventListener('click', function () { row.remove(); });
    $(listId).appendChild(row);
    Array.prototype.forEach.call(row.querySelectorAll('.js-select'), function (el) { window.bindJsSelect(el); });
  }

  var S = VenderAssignStore.STATUS;

  function statusOfRow(row) {
    var staff = (row.querySelector('input[type="text"]') || { value: '' }).value.trim();
    if (staff) return S.REQUESTED;
    if (row.querySelector('.vendor-fixed')) return S.REQUESTING;
    var sel = row.querySelector('.js-select');
    if (sel && clean(ownText(sel))) return S.BEFORE;
    return null;
  }

  function refreshStatuses() {
    Array.prototype.forEach.call(document.querySelectorAll('#mainList .sub-row, #subList .sub-row'), function (row) {
      var st = statusOfRow(row);
      var tag = row.querySelector('.sub-status');
      tag.className = 'tag sub-status' + (st ? ' ' + st.tag : '');
      tag.textContent = st ? st.label : '';
    });
  }

  function readRows(listId) {
    return Array.prototype.map.call($(listId).querySelectorAll('.sub-row'), function (row) {
      var sel = row.querySelectorAll('.js-select');
      var fixed = row.querySelector('.vendor-fixed');
      return {
        vendor: fixed ? fixed.getAttribute('data-code') : TeacherVenderStore.codeOf(clean(ownText(sel[0]))),
        staff: (row.querySelector('input[type="text"]') || { value: '' }).value.trim(),
        fixed: !!fixed
      };
    }).filter(function (r) {
      return r.staff || (r.vendor && !r.fixed);
    }).map(function (r) {
      return { vendor: r.vendor, staff: r.staff };
    });
  }

  function init(opts) {
    var classId = new URLSearchParams(location.search).get('id');
    var cls = null;
    ClassStore.load().forEach(function (r) { if (r.id === classId) cls = r; });
    if (!cls) {
      MessageDialog.show('対象の登壇依頼が見つかりません', function () { location.href = 'vender_assign_list.html'; });
      return;
    }
    var c = ClassStore.COURSES[cls.courseCode];
    $('subLine').textContent = cls.lessonNo + '　' + (c ? c.name : cls.courseCode) + '　予定講師数：メイン' + (cls.mainTeachers || '-') + '人・サブ' + (cls.subTeachers || '-') + '人';

    var a = VenderAssignStore.find(classId);
    var zanNow = a.mains.length < (parseInt(cls.mainTeachers, 10) || 0) || a.subs.length < (parseInt(cls.subTeachers, 10) || 0);
    var zanTag = document.createElement('span');
    zanTag.className = 'tag ' + (zanNow ? 'orange' : 'green');
    zanTag.textContent = zanNow ? 'あり' : 'なし';
    $('subLine').appendChild(document.createTextNode('　残講師：'));
    $('subLine').appendChild(zanTag);
    var planMain = parseInt(cls.mainTeachers, 10) || 0;
    var planSub = parseInt(cls.subTeachers, 10) || 0;
    var mainRows = a.mains.slice();
    var reqs = VenderAssignStore.requestsOf(a);
    var reqNames = {};
    reqs.forEach(function (rq) { reqNames[TeacherVenderStore.nameOf(rq.vendor) || rq.vendor] = rq.vendor; });
    if (reqs.length) $('withdrawBtn').style.display = '';
    $('withdrawBtn').addEventListener('click', function () {
      chooseWithdraw(Object.keys(reqNames)).then(function (name) {
        if (!name) return;
        var code = reqNames[name];
        var rec = VenderAssignStore.find(classId);
        rec.requests = VenderAssignStore.requestsOf(rec).filter(function (r) { return r.vendor !== code; });
        delete rec.requested;
        delete rec.requestMain;
        delete rec.requestSub;
        delete rec.requestVendor;
        VenderAssignStore.upsert(rec);
        location.href = 'vender_assign_list.html';
      });
    });
    if (reqs.length) {
      reqs.forEach(function (rq) {
        for (var mq = 0; mq < (rq.main || 0); mq++) mainRows.push({ vendor: rq.vendor, staff: '', locked: !!rq.vendor });
      });
    } else {
      while (mainRows.length < planMain) mainRows.push({ vendor: '', staff: '' });
    }
    var subRows = a.subs.slice();
    if (reqs.length) {
      reqs.forEach(function (rq) {
        for (var sq = 0; sq < (rq.sub || 0); sq++) subRows.push({ vendor: rq.vendor, staff: '', locked: !!rq.vendor });
      });
    } else {
      while (subRows.length < planSub) subRows.push({ vendor: '', staff: '' });
    }
    mainRows.forEach(function (m) { makeRow('mainList', m); });
    subRows.forEach(function (s) { makeRow('subList', s); });
    $('attendeeVendor').value = a.attendeeVendor || '';
    $('attendee').value = a.attendee || '';
    $('motivationVendor').value = a.motivationVendor || '';
    $('motivationStaff').value = a.motivationStaff || '';
    $('memo').value = a.memo || '';

    function addRow(listId, plan, label) {
      var add = function () { makeRow(listId, { vendor: '', staff: '' }); };
      if ($(listId).querySelectorAll('.sub-row').length < plan) {
        add();
        return;
      }
      MessageDialog.confirm('予定講師数（' + label + plan + '人）を超えます。追加しますか？').then(function (ok) {
        if (ok) add();
      });
    }
    $('addMain').addEventListener('click', function () { addRow('mainList', planMain, 'メイン'); });
    $('addSub').addEventListener('click', function () { addRow('subList', planSub, 'サブ'); });
    refreshStatuses();
    document.addEventListener('input', refreshStatuses);
    document.addEventListener('click', function () { setTimeout(refreshStatuses, 0); }, true);

    $('saveBtn').addEventListener('click', function () {
      var mains = readRows('mainList');
      var subs = readRows('subList');
      if (reqs.length) {
        var noVendor = Array.prototype.some.call(document.querySelectorAll('#mainList .sub-row, #subList .sub-row'), function (row) {
          var staffInput = row.querySelector('input[type="text"]');
          if (!staffInput || !staffInput.value.trim()) return false;
          var sel = row.querySelector('.js-select');
          return !!sel && sel.textContent.replace('▾', '').trim() === '選択してください';
        });
        if (noVendor) {
          MessageDialog.required(['依頼中の会社名']);
          return;
        }
      }
      var record = {
        classId: classId,
        mainCount: a.mainCount,
        subCount: a.subCount,
        mains: mains,
        subs: subs,
        attendeeVendor: $('attendeeVendor').value.trim(),
        attendee: $('attendee').value.trim(),
        motivationVendor: $('motivationVendor').value.trim(),
        motivationStaff: $('motivationStaff').value.trim(),
        memo: $('memo').value
      };
      VenderAssignStore.upsert(Object.assign({}, a, record));
      location.href = 'vender_assign_list.html';
    });
  }

  window.VenderAssignEditor = { init: init };
})();
