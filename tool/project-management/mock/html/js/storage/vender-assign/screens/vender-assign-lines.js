(function () {
  var SPACER = '<span class="check-box check-sm vender-assign-import-spacer"><input type="checkbox"><span class="check-mark"></span></span> ';

  function stateLabel(s, extra) {
    return '<span class="status-label state-tag ' + (extra ? extra + ' ' : '') + s.color + '">' + esc(s.name) + '</span>';
  }

  function checkBox(role, pending, key) {
    return '<label class="check-box check-sm vender-assign-import-check-label' + (pending ? ' is-locked' : '') + '"><input type="checkbox" class="export-check" data-role="' + role + '"' + (key ? ' data-key="' + key + '"' : '') + (pending ? ' data-pending="1" disabled' : '') + ' checked><span class="check-mark"></span></label> ';
  }

  function build(r, vendorCode, opts) {
    opts = opts || {};
    var a = VenderAssignStore.find(r.id);
    var S = VenderAssignStore.STATUS;
    var check = !!opts.check;
    var cls = check ? ' class="vender-assign-import-line"' : '';
    var tagCls = check ? 'vender-assign-import-state-tag' : '';
    var out = { main: [], sub: [], special: [] };
    var specials = a.specials || [];

    function listOf(role) {
      if (role === 'main') return a.mains;
      if (role === 'sub') return a.subs;
      return specials;
    }
    function statusOf(p) {
      if (p.state === 'done') return S.REQUESTED;
      if (p.state === 'requesting') return S.REQUESTING;
      if (p.state === 'before') return S.BEFORE;
      return null;
    }
    function codeOf(p) {
      if (p.state === 'done') return 'REQUESTED';
      if (p.state === 'requesting') return 'REQUESTING';
      return 'BEFORE';
    }
    function prefix(role, can, pending, key) {
      if (!check) return '';
      return can ? checkBox(role, pending, key) : SPACER;
    }
    var vf = function (x) { return !vendorCode || x.vendor === vendorCode; };
    function push(role, rank, html) {
      out[role].push({ r: rank, h: html });
    }
    var ROLES = ['main', 'sub', 'special'];

    ROLES.forEach(function (role) {
      listOf(role).forEach(function (p, i) {
        if (!vf(p)) return;
        var st = statusOf(p);
        var can = !!vendorCode && p.vendor === vendorCode && p.state === 'before';
        push(role, SlotStatusStore.order(codeOf(p)), '<div' + cls + ' data-vendor="' + esc(p.vendor || '') + '">' + prefix(role, can, false, 'b|' + role + '|' + i) + (st ? stateLabel(st, tagCls) + ' ' : '') + esc(TeacherVenderStore.nameOf(p.vendor) || '-') + '：' + esc(p.teacherName || '') + '</div>');
      });
    });

    VenderAssignStore.requestsOf(a).filter(vf).forEach(function (rq) {
      var reqText = stateLabel(S.REQUESTING, tagCls) + ' ' + esc(TeacherVenderStore.nameOf(rq.vendor) || '-') + '： ';
      var pendable = !!opts.includePend && rq.vendor === vendorCode;
      var rank = SlotStatusStore.order('REQUESTING');
      ROLES.forEach(function (role) {
        var n = role === 'main' ? (rq.main || 0) : (role === 'sub' ? (rq.sub || 0) : (rq.special || 0));
        for (var i = 0; i < n; i++) push(role, rank, '<div' + cls + ' data-vendor="' + esc(rq.vendor) + '">' + prefix(role, pendable, true) + reqText + '</div>');
      });
    });

    var planOf = {
      main: parseInt(r.mainTeachers, 10) || 0,
      sub: parseInt(r.subTeachers, 10) || 0,
      special: parseInt(r.specialTeachers, 10) || 0
    };
    var reqOnly = { main: 0, sub: 0, special: 0 };
    VenderAssignStore.requestsOf(a).forEach(function (q) {
      reqOnly.main += q.main || 0;
      reqOnly.sub += q.sub || 0;
      reqOnly.special += q.special || 0;
    });
    var openRank = SlotStatusStore.order('OPEN');
    ROLES.forEach(function (role) {
      var free = Math.max(0, planOf[role] - listOf(role).length - reqOnly[role]);
      for (var k = 0; k < free; k++) push(role, openRank, '<div' + cls + ' data-vendor="">' + prefix(role, true, false) + stateLabel(S.OPEN, tagCls) + '</div>');
    });

    function joinParts(list) {
      if (!list.length) return '-';
      return list.slice().sort(function (x, y) { return x.r - y.r; }).map(function (x) { return x.h; }).join('');
    }

    return {
      main: joinParts(out.main),
      sub: joinParts(out.sub),
      special: joinParts(out.special)
    };
  }

  window.VenderLines = { build: build };
})();
