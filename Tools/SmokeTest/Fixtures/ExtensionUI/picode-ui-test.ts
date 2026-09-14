// Throwaway Pi extension used by Tools/SmokeTest/run-extension.sh.
//
// It registers one command that exercises every surface of Pi's extension UI
// sub-protocol in RPC mode. The harness sends `/picode-ui-test`, which Pi
// executes locally: extension commands never reach a model, so the test costs
// nothing and does not need a configured provider.
//
// No imports: the file is loaded straight from a temporary extension directory,
// so it must not depend on module resolution.

export default function (pi) {
  pi.registerCommand("picode-ui-test", {
    description: "Exercises every RPC extension UI surface without calling a model",
    handler: async (_args, ctx) => {
      // --- fire and forget: Pi emits these and never waits for a response ----
      ctx.ui.notify("PICODE:notify info", "info");
      ctx.ui.notify("PICODE:notify warning", "warning");
      ctx.ui.notify("PICODE:notify error", "error");
      ctx.ui.setStatus("picode-status", "PICODE:status");
      ctx.ui.setStatus("picode-status-cleared", "PICODE:temporary");
      ctx.ui.setStatus("picode-status-cleared", undefined);
      ctx.ui.setWidget("picode-widget", ["PICODE:widget above 1", "PICODE:widget above 2"]);
      ctx.ui.setWidget("picode-widget-below", ["PICODE:widget below"], { placement: "belowEditor" });
      ctx.ui.setWidget("picode-widget-cleared", ["PICODE:temporary widget"]);
      ctx.ui.setWidget("picode-widget-cleared", undefined);
      ctx.ui.setTitle("PICODE:title");
      ctx.ui.setEditorText("PICODE:editor text");

      // --- dialogs: each blocks until the client answers --------------------
      const select = await ctx.ui.select("PICODE:select", ["alpha", "beta", "gamma"]);
      const confirm = await ctx.ui.confirm("PICODE:confirm", "PICODE:message");
      const input = await ctx.ui.input("PICODE:input", "PICODE:placeholder");
      const editor = await ctx.ui.editor("PICODE:editor", "PICODE:prefill");
      // Cancelled by the client (Escape / dismiss) => undefined.
      const cancel = await ctx.ui.input("PICODE:cancel", "cancel me");

      // --- a dialog the client deliberately never answers -------------------
      // Pi resolves this itself when the timeout expires (false for confirm),
      // so PiCode must not leave a stale dialog on screen.
      const timedOut = await ctx.ui.confirm("PICODE:timeout", "PICODE:times out", { timeout: 1500 });

      // The status and widget the harness asserts on are deliberately left set;
      // the ones cleared above prove the clear path.

      // Report every result back through a channel the harness can read.
      ctx.ui.notify(
        "PICODE:results " +
          [
            `select=${select}`,
            `confirm=${confirm}`,
            `input=${input}`,
            `editor=${editor}`,
            `cancel=${cancel}`,
            `timeout=${timedOut}`,
          ].join(" "),
        "info"
      );
    },
  });
}
