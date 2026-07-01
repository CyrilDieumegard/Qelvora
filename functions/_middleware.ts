import { trackAICrawlerRequest } from "@datafast/ai-crawl";

export async function onRequest(context) {
  trackAICrawlerRequest(context.request, context, {
    websiteId: "dfid_W7eRzb8fvbMBhDLkI1X2d",
  });

  return context.next();
}
