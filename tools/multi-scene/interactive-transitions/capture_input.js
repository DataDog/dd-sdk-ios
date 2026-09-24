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
