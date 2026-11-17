(function () {

  var raw = sessionStorage.getItem('venderImportPlan');
  var plan = raw ? JSON.parse(raw) : null;
  var noPlan = !plan || !plan.updates || !plan.updates.length;
  if (noPlan) {
    plan = { updates: [], errors: [], vendorName: '', vendorCode: '' };
    var card = document.querySelector('.modal-body .table-card');
    if (card) card.style.display = 'none';
  }

  $('vendorLine').textContent = plan.vendorName || plan.vendorCode;

  function vendorText(v) {
    return TeacherVenderStore.nameOf(v) || v;
  }

  var STATE_TAG = (function () {
    var ST = VenderAssignStore.STATUS;
    return { done: ST.REQUESTED, requesting: ST.REQUESTING, before: ST.BEFORE, none: ST.OUT_OF_PLAN, open: ST.OPEN };
  })();

  var TAG_STYLE = 'font-size:10px;';

  function tagOf(key) {
    return VenderAssignStore.tag(STATE_TAG[key], TAG_STYLE, 'fixed');
  }

  function afterHtml(on, from, isNew) {
    if (!isNew) return tagOf(on ? 'done' : from);
    return tagOf('done');
  }

  function sameTeacher(p, q) {
    return vendorText(q.vendor) === vendorText(p.vendor) && String(q.teacherName || '').trim() === String(p.teacherName || '').trim();
  }

  function alreadyDone(p, list) {
    return list.some(function (q) { return q.state === 'done' && sameTeacher(p, q); });
  }

  function existingOf(u) {
    var a = VenderAssignStore.find(u.classId) || {};
    return { mains: a.mains || [], subs: a.subs || [] };
  }

  var chk = {};
  var rep = {};
  var asg = {};

  function nextSlot(p) {
    if (p.slot > 0) { p.slot--; return 'before'; }
    if (p.req > 0) { p.req--; return 'requesting'; }
    if (p.free > 0) { p.free--; return 'open'; }
    return 'none';
  }

  function consumeSlot(p, t) {
    if (t === 'before') p.slot--;
    else if (t === 'requesting') p.req--;
    else if (t === 'open') p.free--;
  }


  function cellHtml(u, idx, role, existing, add) {
    var rec = VenderAssignStore.find(u.classId) || {};
    var reqInit = VenderAssignStore.requestsOf(rec).filter(function (r) { return r.vendor === plan.vendorCode; })
      .reduce(function (t, r) { return t + (role === 'sub' ? (r.sub || 0) : (r.main || 0)); }, 0);
    var slotInit = existing.filter(function (p) { return p.state === 'before' && !p.teacherName && p.vendor === plan.vendorCode; }).length;
    var matched = function (p) { return existing.filter(function (q) { return sameTeacher(p, q); })[0]; };
    var clsRec = ClassStore.load().filter(function (r) { return String(r.id) === String(u.classId); })[0] || {};
    var planN = parseInt(role === 'sub' ? clsRec.subTeachers : clsRec.mainTeachers, 10) || 0;
    var reqAll = VenderAssignStore.requestsOf(rec).reduce(function (t, r) { return t + (role === 'sub' ? (r.sub || 0) : (r.main || 0)); }, 0);
    var freeInit = Math.max(0, planN - existing.length - reqAll);
    var freeCount = add.filter(function (p) { return !matched(p); }).length;
    var slotHide = Math.min(freeCount, slotInit);
    var SPACER = '<span class="check-box check-sm" style="visibility:hidden;vertical-align:middle;"><input type="checkbox" style="visibility:hidden;"><span class="check-mark"></span></span> ';
    var rows = [];
    existing.forEach(function (m) {
      if (m.vendor !== plan.vendorCode) return;
      if (add.some(function (p) { return sameTeacher(p, m) && m.state !== 'done'; })) return;
      if (slotHide > 0 && m.state === 'before' && !m.teacherName && m.vendor === plan.vendorCode) { slotHide--; return; }
      var t = STATE_TAG[m.state];
      rows.push('<div style="margin:2px 0;">' + SPACER + (t ? VenderAssignStore.tag(t, TAG_STYLE, 'fixed') + ' ' : '') + '<span class="import-name">' + esc(m.teacherName) + '</span></div>');
    });
    var pool = { slot: slotInit, req: reqInit, free: freeInit };
    add.forEach(function (p, i) {
      var k = idx + '|' + role + '|' + i;
      if (alreadyDone(p, existing) || matched(p)) return;
      if (chk[k] === true && asg[k] && asg[k] !== 'none') consumeSlot(pool, asg[k]);
    });
    add.forEach(function (p, i) {
      var k = idx + '|' + role + '|' + i;
      if (alreadyDone(p, existing) || matched(p)) return;
      if (chk[k] === undefined) chk[k] = pool.slot > 0 || pool.req > 0;
      if (chk[k] && (asg[k] === undefined || asg[k] === 'none')) asg[k] = nextSlot(pool);
    });
    var peek = { slot: pool.slot, req: pool.req, free: pool.free };
    add.forEach(function (p, i) {
      if (alreadyDone(p, existing)) return;
      var k = idx + '|' + role + '|' + i;
      var same = matched(p);
      var from, on;
      if (same) {
        from = same.state;
        if (chk[k] === undefined) chk[k] = same.state !== 'done';
        on = chk[k];
      } else {
        on = chk[k];
        from = on ? asg[k] : nextSlot(peek);
      }
      var replaceOpts = existing.map(function (m, k) { return { m: m, k: k }; }).filter(function (o) {
        return o.m.state !== 'done' && o.m.vendor === plan.vendorCode && String(o.m.teacherName || '').trim()
          && !add.some(function (p) { return sameTeacher(p, o.m); });
      });
      var rv = rep[k] || '';
      var sel = (on && from === 'none' && replaceOpts.length) ? '<span class="replace-mark import-replace-mark" data-key="' + k + '" data-options="' + esc(replaceOpts.map(function (o) { return o.m.teacherName; }).join(',')) + '" title="講師の入れ替え">⇄</span>' + (rv ? '<span style="margin-left:4px;font-size:11px;color:#5a6376;">' + esc(rv) + '</span>' : '') : '';
      rows.push('<div class="import-line" data-key="' + k + '" data-from="' + from + '" style="margin:2px 0;"><label class="check-box check-sm" style="vertical-align:middle;"><input type="checkbox" class="import-check" data-idx="' + idx + '" data-role="' + role + '" data-i="' + i + '"' + (on ? ' checked' : '') + '><span class="check-mark"></span></label> ' +
        tagOf(from) + ' <span>→</span> <span class="js-after">' + afterHtml(on, from, !same) + '</span> ' +
        esc(p.teacherName) + sel + '</div>');
    });
    return rows.length ? rows.join('') : '-';
  }

  var newTotal = 0;
  plan.updates.forEach(function (u) {
    var ex = existingOf(u);
    (u.mains || []).forEach(function (p) { if (!alreadyDone(p, ex.mains)) newTotal++; });
    (u.subs || []).forEach(function (p) { if (!alreadyDone(p, ex.subs)) newTotal++; });
  });
  if (!newTotal && !noPlan) {
    sessionStorage.removeItem('venderImportPlan');
    var tableCard = document.querySelector('.modal-body .table-card');
    if (tableCard) tableCard.style.display = 'none';
    MessageDialog.show('反映する内容がありません');
  }
  if (newTotal) plan.updates.forEach(function (u, idx) {
    var ex = existingOf(u);
    var tr = document.createElement('tr');
    tr.setAttribute('data-idx', idx);
    tr.innerHTML =
      '<td>' + esc(yearLabel(u.year)) + '</td>' +
      '<td><div>' + esc(u.courseName) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(u.courseCode) + '</div></td>' +
      '<td>' + esc(u.lessonNo) + '</td>' +
      '<td>' + esc(u.start) + '</td>' +
      '<td>' + esc(u.end) + '</td>' +
      '<td data-role="main">' + cellHtml(u, idx, 'main', ex.mains, u.mains) + '</td>' +
      '<td data-role="sub">' + cellHtml(u, idx, 'sub', ex.subs, u.subs) + '</td>';
    $('importBody').appendChild(tr);
  });
  document.querySelectorAll('#importBody .js-select').forEach(function (el) { window.bindJsSelect(el); });

  function fitColumns() {
    var table = $('importBody').closest('table');
    var ths = table.querySelectorAll('thead th');
    [5, 6].forEach(function (c) {
      var th = ths[c];
      var need = 0;
      Array.prototype.forEach.call($('importBody').querySelectorAll('tr'), function (tr) {
        var td = tr.children[c];
        if (!td) return;
        td.style.whiteSpace = 'nowrap';
        need = Math.max(need, td.scrollWidth + td.offsetWidth - td.clientWidth);
        td.style.whiteSpace = '';
      });
      var cur = th.offsetWidth;
      if (need > cur) {
        var diff = need - cur;
        th.style.width = need + 'px';
        th.style.minWidth = need + 'px';
        table.style.width = (table.offsetWidth + diff) + 'px';
      }
    });
  }
  fitColumns();

  updateCount();

  if (plan.errors && plan.errors.length) {
    var msg = '反映できない内容（' + plan.errors.length + '件）:\n' + plan.errors.slice(0, 10).join('\n');
    if (plan.errors.length > 10) msg += '\nほか' + (plan.errors.length - 10) + '件';
    $('errorBox').textContent = msg;
  }

  function checkedBoxes() {
    return Array.prototype.slice.call($('importBody').querySelectorAll('.import-check:checked'));
  }

  function updateCount() {
    $('importTotal').textContent = checkedBoxes().length;
  }

  function captureTd(td) {
    var changed = false;
    td.querySelectorAll('.import-line').forEach(function (line) {
      var k = line.getAttribute('data-key');
      chk[k] = line.querySelector('.import-check').checked;
    });
    return changed;
  }

  function chooseReplace(names, newName) {
    return new Promise(function (resolve) {
      var overlay = document.createElement('div');
      overlay.className = 'overlay';
      overlay.innerHTML =
        '<div class="input-dialog">' +
          '<div class="input-dialog-title">講師の入れ替え</div>' +
          '<label class="input-dialog-label">入れ替え前</label>' +
          '<div class="form-control js-select" data-options="' + esc(names.join(',')) + '" data-value="">選択<span class="caret">▾</span></div>' +
          '<label class="input-dialog-label">入れ替え後</label>' +
          '<div class="input-dialog-name">' + esc(newName) + '</div>' +
          '<div class="input-dialog-error"></div>' +
          '<div class="input-dialog-actions">' +
            '<div class="search-btn rp-cancel">キャンセル</div>' +
            '<div class="btn primary rp-ok">入れ替え</div>' +
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

      overlay.querySelector('.rp-ok').addEventListener('click', function () {
        var name = sel.getAttribute('data-value') || '';
        if (!name || names.indexOf(name) === -1) {
          errorEl.textContent = '入れ替える講師を選択してください';
          return;
        }
        close(name);
      });
      overlay.querySelector('.rp-cancel').addEventListener('click', function () { close(null); });
      overlay.addEventListener('click', function (e) { if (e.target === overlay) close(null); });
      document.addEventListener('keydown', onKey);
    });
  }

  function rerender(td) {
    var idx = Number(td.parentNode.getAttribute('data-idx'));
    var role = td.getAttribute('data-role');
    var u = plan.updates[idx];
    var ex = existingOf(u);
    td.innerHTML = role === 'sub' ? cellHtml(u, idx, 'sub', ex.subs, u.subs) : cellHtml(u, idx, 'main', ex.mains, u.mains);
    td.querySelectorAll('.js-select').forEach(function (el) { window.bindJsSelect(el); });
    fitColumns();
  }

  $('importBody').addEventListener('change', function (e) {
    if (!e.target.classList.contains('import-check')) return;
    var td = e.target.closest('td');
    delete asg[e.target.closest('.import-line').getAttribute('data-key')];
    captureTd(td);
    rerender(td);
    updateCount();
  });

  $('importBody').addEventListener('click', function (e) {
    var mark = e.target.closest('.import-replace-mark');
    if (!mark) return;
    var k = mark.getAttribute('data-key');
    var names = (mark.getAttribute('data-options') || '').split(',');
    var parts = k.split('|');
    var src = parts[1] === 'sub' ? plan.updates[Number(parts[0])].subs : plan.updates[Number(parts[0])].mains;
    var newName = src[Number(parts[2])].teacherName;
    chooseReplace(names, newName).then(function (name) {
      if (!name) return;
      var td = mark.closest('td');
      captureTd(td);
      rep[k] = name;
      chk[k] = true;
      rerender(td);
      updateCount();
    });
  });
  updateCount();

  function mergeUnique(list, add) {
    add.forEach(function (p) {
      var same = list.filter(function (q) { return sameTeacher(p, q); })[0];
      if (!same) {
        var slot = list.filter(function (q) { return q.state === 'before' && !q.teacherName && q.vendor === p.vendor; })[0];
        if (slot) { slot.teacherName = p.teacherName; slot.state = 'done'; } else { list.push(p); }
        return;
      }
      if (same.state !== 'done') same.state = 'done';
    });
    return list;
  }

  function transform(a, pick) {
    (pick.dropMains || []).filter(function (v, k, arr) { return arr.indexOf(v) === k; }).sort(function (x, y) { return y - x; }).forEach(function (k) { a.mains.splice(k, 1); });
    (pick.dropSubs || []).filter(function (v, k, arr) { return arr.indexOf(v) === k; }).sort(function (x, y) { return y - x; }).forEach(function (k) { a.subs.splice(k, 1); });
    var beforeM = a.mains.length;
    var beforeS = a.subs.length;
    a.mains = mergeUnique(a.mains, pick.mains);
    a.subs = mergeUnique(a.subs, pick.subs);
    var addM = a.mains.length - beforeM;
    var addS = a.subs.length - beforeS;
    var reqs = VenderAssignStore.requestsOf(a).map(function (r) {
      return { vendor: r.vendor, main: r.main || 0, sub: r.sub || 0 };
    });
    reqs.forEach(function (r) {
      if (r.vendor !== plan.vendorCode) return;
      var t = Math.min(r.main, addM);
      r.main -= t;
      addM -= t;
      t = Math.min(r.sub, addS);
      r.sub -= t;
      addS -= t;
    });
    a.requests = reqs.filter(function (r) { return r.main > 0 || r.sub > 0; });
    delete a.requested;
    delete a.requestMain;
    delete a.requestSub;
    delete a.requestVendor;
    return a;
  }

  function sumReq(a, role) {
    return VenderAssignStore.requestsOf(a).reduce(function (t, r) { return t + (r[role] || 0); }, 0);
  }

  function totals(a) {
    return { m: a.mains.length + sumReq(a, 'main'), s: a.subs.length + sumReq(a, 'sub') };
  }

  function overInfo(u, before, after) {
    var cls = ClassStore.load().filter(function (r) { return String(r.id) === String(u.classId); })[0];
    if (!cls) return null;
    var planM = parseInt(cls.mainTeachers, 10);
    var planS = parseInt(cls.subTeachers, 10);
    var info = { classId: u.classId, lines: [], mainTeachers: null, subTeachers: null };
    if (!isNaN(planM) && after.m > planM && after.m > before.m) {
      info.lines.push('　メイン：予定 ' + planM + '人 → ' + after.m + '人');
      info.mainTeachers = String(after.m);
    }
    if (!isNaN(planS) && after.s > planS && after.s > before.s) {
      info.lines.push('　サブ：予定 ' + planS + '人 → ' + after.s + '人');
      info.subTeachers = String(after.s);
    }
    if (!info.lines.length) return null;
    info.lines.unshift('・' + u.courseCode + '　' + u.courseName + '　' + u.lessonNo);
    return info;
  }

  function applyPlan(infos) {
    if (!infos.length) return;
    var classes = ClassStore.load();
    classes.forEach(function (r) {
      infos.forEach(function (i) {
        if (String(i.classId) !== String(r.id)) return;
        if (i.mainTeachers !== null) r.mainTeachers = i.mainTeachers;
        if (i.subTeachers !== null) r.subTeachers = i.subTeachers;
      });
    });
    ClassStore.save(classes);
  }

  function commit(picked, infos) {
    var people = 0;
    try {
      Object.keys(picked).forEach(function (key) {
        var u = plan.updates[Number(key)];
        var a = transform(VenderAssignStore.find(u.classId), picked[key]);
        VenderAssignStore.upsert(a);
        people += picked[key].mains.length + picked[key].subs.length;
      });
      applyPlan(infos);
    } catch (e) {
      MessageDialog.show('反映に失敗しました（' + e.message + '）');
      return;
    }
    sessionStorage.removeItem('venderImportPlan');
    var msg = '反映が完了しました\n反映: ' + people + '人（' + Object.keys(picked).length + 'クラス）';
    MessageDialog.show(msg, function () { location.href = 'vender_assign_list.html'; });
  }

  $('importApply').addEventListener('click', function () {
    if (!checkedBoxes().length) {
      MessageDialog.show('反映する内容がありません');
      return;
    }
    var picked = {};
    var usedTargets = {};
    var dupName = '';
    checkedBoxes().forEach(function (cb) {
      var idx = Number(cb.getAttribute('data-idx'));
      var role = cb.getAttribute('data-role');
      var i = Number(cb.getAttribute('data-i'));
      var u = plan.updates[idx];
      picked[idx] = picked[idx] || { mains: [], subs: [], dropMains: [], dropSubs: [] };
      var src = role === 'sub' ? u.subs : u.mains;
      picked[idx][role === 'sub' ? 'subs' : 'mains'].push(src[i]);
      var chosen = rep[cb.closest('.import-line').getAttribute('data-key')] || '';
      if (chosen) {
        var tkey = idx + '|' + role + '|' + chosen;
        if (usedTargets[tkey]) dupName = dupName || chosen;
        usedTargets[tkey] = true;
        var rec = VenderAssignStore.find(u.classId);
        var list = role === 'sub' ? rec.subs : rec.mains;
        var k = list.findIndex(function (m) { return m.state !== 'done' && String(m.teacherName || '').trim() === chosen; });
        if (k >= 0) picked[idx][role === 'sub' ? 'dropSubs' : 'dropMains'].push(k);
      }
    });
    if (dupName) {
      MessageDialog.show('同じ講師「' + dupName + '」を複数の講師と置き換えることはできません');
      return;
    }
    var infos = [];
    try {
      Object.keys(picked).forEach(function (key) {
        var u = plan.updates[Number(key)];
        var a = VenderAssignStore.find(u.classId);
        var info = overInfo(u, totals(a), totals(transform(JSON.parse(JSON.stringify(a)), picked[key])));
        if (info) infos.push(info);
      });
    } catch (e) {
      MessageDialog.show('反映に失敗しました（' + e.message + '）');
      return;
    }
    if (infos.length) {
      var lines = [].concat.apply([], infos.map(function (i) { return i.lines; }));
      MessageDialog.confirm(['予定講師数を超えています', '', '以下に反映してよろしいですか？'].concat(lines).join('\n')).then(function (ok) {
        if (ok) commit(picked, infos);
      });
      return;
    }
    commit(picked, []);
  });
})();
