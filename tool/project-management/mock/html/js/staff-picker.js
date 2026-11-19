(function () {
  var EMPTY = 'すべて';
  var COLS = 8;
  var PLACEHOLDER = '';

  function names(list) {
    return list.map(function (x) { return x.name; });
  }

  function colorMap(list) {
    var map = {};
    list.forEach(function (t) { map[t.code] = t.color; });
    return map;
  }

  function field(label, id, items, size) {
    return '<div class="field"><label>' + label + '</label>' +
      '<div class="control ' + (size || 'small') + ' js-select" id="' + id + '" data-options="' + esc([EMPTY].concat(items).join(',')) + '" data-value="">' + EMPTY + '<span class="caret">▾</span></div></div>';
  }

  function valueOf(id) {
    var v = document.getElementById(id).getAttribute('data-value') || '';
    return v === EMPTY ? '' : v;
  }

  function passes(s, f, exclude) {
    if (s.status === OperatingStatusStore.nameOf('STOPPED')) return false;
    if (exclude.indexOf(s.code) !== -1) return false;
    if (f.affiliation && s.affiliation !== f.affiliation) return false;
    if (f.vender && s.company !== StaffVenderStore.codeOf(f.vender)) return false;
    if (f.role && !(s.roles || []).some(function (c) { return StaffRoleStore.nameOf(c) === f.role; })) return false;
    if (f.job && !(s.jobTypes || []).some(function (c) { return JobTypeStore.nameOf(c) === f.job; })) return false;
    return true;
  }

  function rowHtml(s, maps) {
    var partner = s.affiliation === AffiliationStore.nameOf('PARTNER');
    var roles = (s.roles || []).map(function (r) {
      return '<span class="tag role-tag ' + (maps.role[r] || '') + '">' + esc(StaffRoleStore.nameOf(r)) + '</span>';
    }).join('');
    var jobs = (s.jobTypes || []).map(function (j) {
      return '<span class="tag job-type-tag ' + (maps.job[j] || '') + '">' + esc(JobTypeStore.nameOf(j)) + '</span>';
    }).join('');
    var positions = (s.positions || []).map(function (p) {
      return '<span class="tag position-tag ' + (maps.pos[p] || '') + '">' + esc(PositionStore.nameOf(p)) + '</span>';
    }).join('');
    return '<tr data-code="' + esc(s.code) + '">' +
      '<td><input type="radio" name="spPick" value="' + esc(s.code) + '"></td>' +
      '<td>' + esc(s.name) + '</td>' +
      '<td>' + esc(s.code) + '</td>' +
      '<td><span class="tag affiliation-tag ' + (partner ? 'orange' : 'blue') + '">' + esc(s.affiliation) + '</span></td>' +
      '<td>' + (s.company ? esc(StaffVenderStore.nameOf(s.company)) : '-') + '</td>' +
      '<td><div class="tag-stack">' + roles + '</div></td>' +
      '<td><div class="tag-stack">' + jobs + '</div></td>' +
      '<td><div class="tag-stack">' + (positions || '-') + '</div></td>' +
      '</tr>';
  }

  function open(opts) {
    var exclude = opts.exclude || [];
    var selected = opts.current || '';
    return new Promise(function (resolve) {
      var overlay = document.createElement('div');
      overlay.className = 'overlay';
      overlay.innerHTML =
        '<div class="modal modal-wide">' +
          '<div class="modal-header"><div><h2 class="modal-header-title">実施担当者選択</h2></div><a class="close-x" id="spClose">✕</a></div>' +
          '<div class="modal-body picker-body">' +
            '<div class="filter-panel">' +
              '<div class="field"><label>キーワード検索</label><input type="text" class="field-control-input" id="spKeyword" placeholder="実施担当者コード・実施担当者名で検索"></div>' +
              field('所属区分', 'spAffiliation', names(AffiliationStore.load())) +
              field('実施担当ベンダー', 'spVender', names(StaffVenderStore.load()), 'wide') +
              field('担当区分', 'spRole', names(StaffRoleStore.load())) +
              field('業務区分', 'spJob', names(JobTypeStore.load())) +
              '<div class="search-btn" id="spSearch">検索</div>' +
              '<div class="search-btn" id="spReset">リセット</div>' +
            '</div>' +
            '<div class="table-card"><div class="table-meta"><div class="count"><b id="spCount">0</b> 件</div></div>' +
              '<div class="table-scroll"><table><thead><tr><th></th><th>実施担当者名</th><th>実施担当者コード</th><th>所属区分</th><th>実施担当ベンダー</th><th>担当区分</th><th>業務区分</th><th>役職</th></tr></thead>' +
              '<tbody id="spBody">' + PLACEHOLDER + '</tbody></table></div></div>' +
          '</div>' +
          '<div class="modal-footer"><div class="search-btn" id="spCancel">キャンセル</div><div class="btn primary" id="spOk">決定</div></div>' +
        '</div>';
      document.body.appendChild(overlay);
      Array.prototype.forEach.call(overlay.querySelectorAll('.js-select'), function (el) { window.bindJsSelect(el); });

      function close(result) {
        overlay.remove();
        resolve(result);
      }

      function render() {
        lastKey = keyOf();
        var f = {
          affiliation: valueOf('spAffiliation'),
          vender: valueOf('spVender'),
          role: valueOf('spRole'),
          job: valueOf('spJob')
        };
        var kw = document.getElementById('spKeyword').value.trim();
        var maps = {
          role: colorMap(StaffRoleStore.load()),
          job: colorMap(JobTypeStore.load()),
          pos: colorMap(PositionStore.load())
        };
        var list = StaffStore.load().filter(function (s) {
          if (kw && s.code.indexOf(kw) === -1 && s.name.indexOf(kw) === -1) return false;
          return passes(s, f, exclude);
        });
        var body = document.getElementById('spBody');
        body.innerHTML = list.map(function (s) { return rowHtml(s, maps); }).join('') || '<tr><td colspan="' + COLS + '">該当する担当者がいません</td></tr>';
        if (kw && list.length === 1) selected = list[0].code;
        document.getElementById('spCount').textContent = list.length;
        Array.prototype.forEach.call(body.querySelectorAll('input[type="radio"]'), function (r) {
          r.checked = r.value === selected;
        });
      }

      document.getElementById('spBody').addEventListener('click', function (e) {
        var tr = e.target.closest('tr[data-code]');
        if (!tr) return;
        selected = tr.getAttribute('data-code');
        tr.querySelector('input[type="radio"]').checked = true;
      });
      document.getElementById('spSearch').addEventListener('click', render);
      document.getElementById('spOk').addEventListener('click', function () {
        if (!selected) return;
        close(selected);
      });
      document.getElementById('spReset').addEventListener('click', function () {
        document.getElementById('spKeyword').value = '';
        Array.prototype.forEach.call(overlay.querySelectorAll('.js-select'), function (el) {
          el.setAttribute('data-value', '');
          el.innerHTML = EMPTY + '<span class="caret">▾</span>';
        });
        document.getElementById('spBody').innerHTML = PLACEHOLDER;
        document.getElementById('spCount').textContent = 0;
      });
      document.getElementById('spCancel').addEventListener('click', function () { close(null); });
      document.getElementById('spClose').addEventListener('click', function () { close(null); });
      var lastKey = '';
      function keyOf() {
        return [valueOf('spAffiliation'), valueOf('spVender'), valueOf('spRole'), valueOf('spJob'), document.getElementById('spKeyword').value.trim()].join('|');
      }
      document.getElementById('spKeyword').value = opts.keyword || '';
      lastKey = keyOf();
      if (opts.keyword) {
        render();
        var rows = document.querySelectorAll('#spBody tr[data-code]');
        if (rows.length === 1) close(rows[0].getAttribute('data-code'));
      }
      overlay.addEventListener('click', function () {
        setTimeout(function () {
          if (keyOf() !== lastKey) render();
        }, 0);
      }, true);
      var kwTimer = null;
      document.getElementById('spKeyword').addEventListener('input', function () {
        clearTimeout(kwTimer);
        kwTimer = setTimeout(render, 250);
      });
    });
  }

  window.StaffPicker = { open: open };
})();
