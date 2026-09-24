// One request remains available for callers that do not use the finite sequence.
async function exchange(settings) {
// Evaluated by the input worker with tools and settings in one awaited execution.
// Native setup/cleanup and visual review of readiness/results remain outside it.
const quote = value => "'" + String(value).replace(/'/g, "'\\''") + "'";
let before, action, selection, dispatchAttempted = false, localPending = null;
async function local(stage, observation) {
    const data = JSON.stringify(stage === 'abort' ? {dispatch_attempted: false} : {observation});
    const delimiter = 'CAPTURE_INPUT_JSON';
    if (data.split('\n').includes(delimiter)) throw new Error('Invalid receipt delimiter');
    let reply = await tools.exec_command({
        cmd: 'python3 -B ' + quote(settings.helper) + ' ' + stage + ' --request ' + quote(settings.request) +
             " <<'" + delimiter + "'\n" + data + '\n' + delimiter,
        sandbox_permissions: 'require_escalated',
        justification: 'Validate and preserve the current supported Xcode capture for the admitted task-only qualification.',
        max_output_tokens: 1500, yield_time_ms: 10000
    });
    let output = reply.output;
    const deadline = Math.min(settings.deadline, Date.now()/1000 + 30);
    while (reply.session_id) {
        localPending = {stage, session_id: reply.session_id, output};
        if (Date.now()/1000 >= deadline) throw new Error('Local capture helper still pending at original bound');
        reply = await tools.write_stdin({session_id: reply.session_id, chars: '', yield_time_ms: 1000, max_output_tokens: 1500});
        output += reply.output;
    }
    localPending = null;
    if (reply.exit_code !== 0) throw new Error('Local ' + stage + ' failed: ' + output);
    return JSON.parse(output);
}
try {
    if (!Number.isFinite(settings.deadline) || Date.now()/1000 >= settings.deadline) throw new Error('Missing or expired original input deadline');
    before = {command: '', interaction_session_key: settings.sessionKey, started_at: Date.now()/1000};
    before.actual_return = await tools.mcp__xcode__DeviceInteractionSynthesize({interactSessionKey: settings.sessionKey, interactionCommand: ''});
    before.finished_at = Date.now()/1000;
    selection = await local('plan', before);
    if (selection.state !== 'READY') return {state: 'STOP', selection, before, dispatch_attempted: false};
    // Recheck after local transport too. An expired bound cannot be renewed.
    if (Date.now()/1000 - before.finished_at > 30 || Date.now()/1000 >= selection.deadline) {
        return {state: 'STOP', result: await local('abort'), before, dispatch_attempted: false};
    }
    action = {command: selection.command, interaction_session_key: settings.sessionKey, started_at: Date.now()/1000};
    dispatchAttempted = true;
    action.actual_return = await tools.mcp__xcode__DeviceInteractionSynthesize({interactSessionKey: settings.sessionKey, interactionCommand: action.command});
    action.finished_at = Date.now()/1000;
    const result = await local('publish', action);
    return {state: 'PUBLISHED', result, before, action, provenance: selection.provenance, dispatch_attempted: true};
} catch (error) {
    // Complete actual returns survive publication errors. A pending local helper
    // or attempted effect is not a zero-input or cleanup acknowledgement.
    return {state: 'STOP', reason: String(error), before, action, selection,
            dispatch_attempted: dispatchAttempted, local_pending: localPending};
}

}
if (!settings.sequenceRoot) return await exchange(settings);

const quote = value => "'" + String(value).replace(/'/g, "'\\''") + "'";
let bound = null, localPending = null, lastExchange = null, index = 0;
async function sequence(stage, payload) {
    const data = JSON.stringify(payload);
    const command = 'python3 -B ' + quote(settings.sequenceHelper) + ' ' + stage +
        ' --root ' + quote(settings.sequenceRoot) + ' --framework ' + quote(settings.framework) +
        " <<'CAPTURE_SEQUENCE_JSON'\n" + data + '\nCAPTURE_SEQUENCE_JSON';
    const limit = bound ? (['record','stop'].includes(stage) ? bound.cleanup_deadline : bound.native_deadline) : Infinity;
    const deadline = Math.min(limit, Date.now()/1000+30);
    let reply = await tools.exec_command({cmd: command, sandbox_permissions: 'require_escalated',
        justification: 'Validate and preserve the admitted capture sequence without changing its original deadlines.',
        max_output_tokens: 2000, yield_time_ms: 1000});
    let output = reply.output;
    while (reply.session_id) {
        localPending = {stage, session_id: reply.session_id, output};
        if (Date.now()/1000 >= deadline) throw new Error('Sequence helper still pending at original bound');
        reply = await tools.write_stdin({session_id: reply.session_id, chars: '', yield_time_ms: 1000, max_output_tokens: 2000});
        output += reply.output;
    }
    localPending = null;
    if (reply.exit_code !== 0) throw new Error('Sequence '+stage+' failed: '+output);
    return JSON.parse(output);
}
try {
    bound = await sequence('bind', {});
    if (bound.state !== 'BOUND' || bound.phase_count !== 11) throw new Error('Invalid canonical sequence binding');
    while (Date.now()/1000 < bound.native_deadline) {
        const binding = {binding_sha256: bound.binding_sha256, index};
        const next = await sequence('next', binding);
        if (next.state === 'WAIT') continue;
        if (next.state === 'TERMINAL') {
            const terminal = await sequence('stop', {...binding, terminal: next, local_pending: null});
            return {state: 'TERMINAL', completed: index, native: next, receipt: terminal.receipt,
                    scope: 'Worker stopped; native/session cleanup remains independently required'};
        }
        if (next.state !== 'REQUEST' || next.index !== index || next.session_key !== bound.session_key)
            throw new Error('Foreign sequence request');
        lastExchange = await exchange({...settings, request: next.request, sessionKey: next.session_key, deadline: next.deadline});
        const saved = await sequence('record', {...binding, result: lastExchange});
        if (saved.state !== 'RECORDED' || lastExchange.state !== 'PUBLISHED' || saved.next_index !== index+1)
            return {state: 'STOP', completed: index, result: lastExchange, publication: saved, local_pending: localPending};
        index = saved.next_index;
        if (typeof notify === 'function') notify({capture_phase: next.phase, state: 'PUBLISHED', completed: index});
    }
    throw new Error('Original native sequence deadline expired');
} catch (error) {
    const result = {state: 'STOP', reason: String(error), completed: index,
                    last_exchange: lastExchange, local_pending: localPending};
    if (bound && !localPending) {
        try { result.stop = await sequence('stop', {binding_sha256: bound.binding_sha256, ...result}); }
        catch (failure) { result.persistence_error = String(failure); result.local_pending = localPending; }
    }
    return result;
}
