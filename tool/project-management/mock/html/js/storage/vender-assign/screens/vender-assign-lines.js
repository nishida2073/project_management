(function () {
  function stateLabel(s) {
    return '<span class="status-label state-tag ' + s.color + '">' + esc(s.name) + '</span>';
  }

  function build(r, vendorCode) {
    var a = VenderAssignStore.find(r.id);
    var S = VenderAssignStore.STATUS;
    function lines(items) {
      return items.length ? items.map(function (x) {
        return '<div data-vendor="' + esc(x.code || '') + '">' + (x.status ? stateLabel(x.status) + ' ' : '') + esc(x.vendor) + '：' + esc(x.teacherName) + '</div>';
      }).join('') : '-';
    }
    function statusOf(p) {
      if (p.state === 'done') return S.REQUESTED;
      if (p.state === 'requesting') return S.REQUESTING;
      if (p.state === 'before') return S.BEFORE;
      return null;
    }
    var vf = function (x) { return !vendorCode || x.vendor === vendorCode; };
    var mainLines = lines(a.mains.filter(vf).map(function (m) {
      return { code: m.vendor, vendor: TeacherVenderStore.nameOf(m.vendor) || '-', teacherName: m.teacherName || '', status: statusOf(m) };
    }));
    var subLines = lines(a.subs.filter(vf).map(function (s) {
      return { code: s.vendor, vendor: TeacherVenderStore.nameOf(s.vendor) || '-', teacherName: s.teacherName || '', status: statusOf(s) };
    }));
    var reqs = VenderAssignStore.requestsOf(a).filter(vf);
    var tot = VenderAssignStore.totalRequest(a);
    reqs.forEach(function (rq) {
      var reqText = stateLabel(S.REQUESTING) + ' ' + esc(TeacherVenderStore.nameOf(rq.vendor) || '-') + '： ';
      for (var mi = 0; mi < (rq.main || 0); mi++) mainLines = (mainLines === '-' ? '' : mainLines) + '<div data-vendor="' + esc(rq.vendor) + '">' + reqText + '</div>';
      for (var si = 0; si < (rq.sub || 0); si++) subLines = (subLines === '-' ? '' : subLines) + '<div data-vendor="' + esc(rq.vendor) + '">' + reqText + '</div>';
    });
    var related = r.related && r.related.length ? r.related.slice().sort(function (a, b) { return String(a).localeCompare(String(b), 'ja', { numeric: true }); }).join(', ') : '-';
    var planMain = parseInt(r.mainTeachers, 10) || 0;
    var planSub = parseInt(r.subTeachers, 10) || 0;
    var reqOnly = VenderAssignStore.requestsOf(a).reduce(function (t, q) { t.main += q.main || 0; t.sub += q.sub || 0; return t; }, { main: 0, sub: 0 });
    var freeMain = Math.max(0, planMain - a.mains.length - reqOnly.main);
    var freeSub = Math.max(0, planSub - a.subs.length - reqOnly.sub);
    for (var fm = 0; fm < freeMain; fm++) mainLines = (mainLines === '-' ? '' : mainLines) + '<div data-vendor="">' + stateLabel(S.OPEN) + '</div>';
    for (var fs = 0; fs < freeSub; fs++) subLines = (subLines === '-' ? '' : subLines) + '<div data-vendor="">' + stateLabel(S.OPEN) + '</div>';

    return { main: mainLines, sub: subLines };
  }

  window.VenderLines = { build: build };
})();
