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
    var out = { main: [], sub: [] };

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

    ['main', 'sub'].forEach(function (role) {
      var list = role === 'main' ? a.mains : a.subs;
      list.forEach(function (p, i) {
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
      for (var mi = 0; mi < (rq.main || 0); mi++) push('main', rank, '<div' + cls + ' data-vendor="' + esc(rq.vendor) + '">' + prefix('main', pendable, true) + reqText + '</div>');
      for (var si = 0; si < (rq.sub || 0); si++) push('sub', rank, '<div' + cls + ' data-vendor="' + esc(rq.vendor) + '">' + prefix('sub', pendable, true) + reqText + '</div>');
    });

    var planMain = parseInt(r.mainTeachers, 10) || 0;
    var planSub = parseInt(r.subTeachers, 10) || 0;
    var reqOnly = VenderAssignStore.requestsOf(a).reduce(function (t, q) { t.main += q.main || 0; t.sub += q.sub || 0; return t; }, { main: 0, sub: 0 });
    var freeMain = Math.max(0, planMain - a.mains.length - reqOnly.main);
    var freeSub = Math.max(0, planSub - a.subs.length - reqOnly.sub);
    var openRank = SlotStatusStore.order('OPEN');
    for (var fm = 0; fm < freeMain; fm++) push('main', openRank, '<div' + cls + ' data-vendor="">' + prefix('main', true, false) + stateLabel(S.OPEN, tagCls) + '</div>');
    for (var fs = 0; fs < freeSub; fs++) push('sub', openRank, '<div' + cls + ' data-vendor="">' + prefix('sub', true, false) + stateLabel(S.OPEN, tagCls) + '</div>');

    function joinParts(list) {
      if (!list.length) return '-';
      return list.slice().sort(function (x, y) { return x.r - y.r; }).map(function (x) { return x.h; }).join('');
    }

    return {
      main: joinParts(out.main),
      sub: joinParts(out.sub)
    };
  }

  window.VenderLines = { build: build };
})();
