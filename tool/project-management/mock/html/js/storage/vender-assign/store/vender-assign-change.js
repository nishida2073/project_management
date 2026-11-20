(function () {
  var LISTS = { main: 'mains', sub: 'subs', special: 'specials' };
  var PLAN = { main: 'mainTeachers', sub: 'subTeachers', special: 'specialTeachers' };

  function listOf(a, role) {
    return a[LISTS[role]] || [];
  }

  function requestsFor(a, code, role) {
    var fromRequests = VenderAssignStore.requestsOf(a).filter(function (q) { return code && q.vendor === code; })
      .reduce(function (t, q) { return t + (q[role] || 0); }, 0);
    var named = listOf(a, role).filter(function (p) { return code && p.vendor === code && p.state === 'requesting'; }).length;
    return fromRequests + named;
  }

  function freeOf(a, cls, role) {
    var plan = parseInt(cls[PLAN[role]], 10) || 0;
    var reqOnly = VenderAssignStore.requestsOf(a).reduce(function (t, q) { return t + (q[role] || 0); }, 0);
    return Math.max(0, plan - listOf(a, role).length - reqOnly);
  }

  function apply(a, code, to, cls) {
    var counts = {};
    var free = {};
    Object.keys(LISTS).forEach(function (role) {
      counts[role] = requestsFor(a, code, role);
      free[role] = (to === 'before' && cls) ? freeOf(a, cls, role) : 0;
    });
    a.requests = VenderAssignStore.requestsOf(a).filter(function (q) { return q.vendor !== code; });
    Object.keys(LISTS).forEach(function (role) {
      a[LISTS[role]] = listOf(a, role).filter(function (p) {
        if (p.vendor !== code) return true;
        if (p.state === 'done') return true;
        if (to === 'open') return false;
        return p.state !== 'requesting';
      });
    });
    if (to === 'before') {
      Object.keys(LISTS).forEach(function (role) {
        for (var n = 0; n < counts[role] + free[role]; n++) {
          a[LISTS[role]].push({ vendor: code, teacherName: '', state: 'before' });
        }
      });
    }
    delete a.requested;
    delete a.requestMain;
    delete a.requestSub;
    delete a.requestVendor;
    return a;
  }

  window.VenderAssignChange = { requestsFor: requestsFor, freeOf: freeOf, apply: apply };
})();
