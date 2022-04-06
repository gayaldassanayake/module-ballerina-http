package io.ballerina.stdlib.http.transport.contractimpl.listener.states.http3;

import io.ballerina.stdlib.http.transport.contract.ServerConnectorFuture;
import io.ballerina.stdlib.http.transport.contractimpl.Http3OutboundRespListener;
import io.ballerina.stdlib.http.transport.contractimpl.common.states.Http3MessageStateContext;
import io.ballerina.stdlib.http.transport.contractimpl.listener.http3.Http3SourceHandler;
import io.ballerina.stdlib.http.transport.message.HttpCarbonMessage;
import io.netty.channel.ChannelHandlerContext;
import io.netty.handler.codec.http.HttpContent;
import io.netty.incubator.codec.http3.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import static io.ballerina.stdlib.http.transport.contract.Constants.REMOTE_CLIENT_CLOSED_WHILE_WRITING_100_CONTINUE_RESPONSE;
import static io.ballerina.stdlib.http.transport.contractimpl.common.states.StateUtil.ILLEGAL_STATE_ERROR;
import static io.netty.handler.codec.http.HttpResponseStatus.CONTINUE;

public class Response100ContinueSent implements ListenerState {
    private static final Logger LOG = LoggerFactory.getLogger(Response100ContinueSent.class);
    private final Http3MessageStateContext http3MessageStateContext;
    private final long streamId;

    public Response100ContinueSent(Http3MessageStateContext http3MessageStateContext, long streamId) {
        this.http3MessageStateContext = http3MessageStateContext;
        this.streamId=streamId;
    }

    @Override
    public void readInboundRequestHeaders(ChannelHandlerContext ctx, Http3HeadersFrame headersFrame, long streamId) {
        LOG.warn("readInboundRequestHeaders {}", ILLEGAL_STATE_ERROR);

    }

    @Override
    public void readInboundRequestBody(Http3SourceHandler http3SourceHandler, Http3DataFrame dataFrame, boolean isLast) throws Http3Exception {
        //Client might start sending request body without waiting for the 100-continue response.
        http3MessageStateContext.setListenerState(new ReceivingEntityBody(http3MessageStateContext,streamId));
        http3MessageStateContext.getListenerState().readInboundRequestBody(http3SourceHandler, dataFrame,isLast);
    }


    @Override
    public void writeOutboundResponseHeaders(Http3OutboundRespListener http3OutboundRespListener, HttpCarbonMessage outboundResponseMsg, HttpContent httpContent, long streamId) throws Http3Exception {
        LOG.warn("writeOutboundResponseHeaders {}", ILLEGAL_STATE_ERROR);

    }

    @Override
    public void writeOutboundResponseBody(Http3OutboundRespListener http3OutboundRespListener, HttpCarbonMessage outboundResponseMsg, HttpContent httpContent, long streamId) throws Http3Exception {
        // Send a '100 Continue' response.
        ChannelHandlerContext ctx = http3OutboundRespListener.getChannelHandlerContext();
        Http3HeadersFrame headersFrame = new DefaultHttp3HeadersFrame();
        headersFrame.headers().status(CONTINUE.codeAsText());
        ctx.write(headersFrame);
        ctx.write(streamId);
        ctx.write(new DefaultHttp3Headers(false));
        ctx.voidPromise();
        ctx.write(ctx.voidPromise());

        http3MessageStateContext.setListenerState(
                new SendingHeaders(http3OutboundRespListener, http3MessageStateContext));

//        addResponseWriteFailureListener(http3OutboundRespListener.getOutboundRespStatusFuture(), channelFuture,
//                http3OutboundRespListener);
    }

    @Override
    public void handleStreamTimeout(ServerConnectorFuture serverConnectorFuture, ChannelHandlerContext ctx, Http3OutboundRespListener http3OutboundRespListener, long streamId) {
//        Http3StateUtil.sendRequestTimeoutResponse(ctx, http3OutboundRespListener, streamId, REQUEST_TIMEOUT,
//                Unpooled.EMPTY_BUFFER, true, true);
    }

    @Override
    public void handleAbruptChannelClosure(ServerConnectorFuture serverConnectorFuture) {
        LOG.error(REMOTE_CLIENT_CLOSED_WHILE_WRITING_100_CONTINUE_RESPONSE);

    }
}
