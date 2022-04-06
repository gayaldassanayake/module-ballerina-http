/*
 *  Copyright (c) 2017, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
 *
 *  WSO2 Inc. licenses this file to you under the Apache License,
 *  Version 2.0 (the "License"); you may not use this file except
 *  in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing,
 *  software distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 *  KIND, either express or implied.  See the License for the
 *  specific language governing permissions and limitations
 *  under the License.
 *
 */

package io.ballerina.stdlib.http.transport.contractimpl;

import io.ballerina.stdlib.http.api.HttpConstants;
import io.ballerina.stdlib.http.transport.contract.Constants;
import io.ballerina.stdlib.http.transport.contract.HttpClientConnector;
import io.ballerina.stdlib.http.transport.contract.HttpWsConnectorFactory;
import io.ballerina.stdlib.http.transport.contract.ServerConnector;
import io.ballerina.stdlib.http.transport.contract.config.ListenerConfiguration;
import io.ballerina.stdlib.http.transport.contract.config.SenderConfiguration;
import io.ballerina.stdlib.http.transport.contract.config.ServerBootstrapConfiguration;
import io.ballerina.stdlib.http.transport.contract.websocket.WebSocketClientConnector;
import io.ballerina.stdlib.http.transport.contract.websocket.WebSocketClientConnectorConfig;
import io.ballerina.stdlib.http.transport.contractimpl.common.Util;
import io.ballerina.stdlib.http.transport.contractimpl.common.ssl.SSLConfig;
import io.ballerina.stdlib.http.transport.contractimpl.common.ssl.SSLHandlerFactory;
import io.ballerina.stdlib.http.transport.contractimpl.listener.ServerConnectorBootstrap;
import io.ballerina.stdlib.http.transport.contractimpl.sender.channel.BootstrapConfiguration;
import io.ballerina.stdlib.http.transport.contractimpl.sender.channel.pool.ConnectionManager;
import io.ballerina.stdlib.http.transport.contractimpl.websocket.DefaultWebSocketClientConnector;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.group.ChannelGroup;
import io.netty.channel.group.DefaultChannelGroup;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.handler.ssl.SslContext;
import io.netty.incubator.codec.http3.Http3;
import io.netty.incubator.codec.quic.QuicSslContext;
import io.netty.incubator.codec.quic.QuicSslContextBuilder;
import io.netty.util.concurrent.DefaultEventExecutorGroup;
import io.netty.util.concurrent.DefaultThreadFactory;
import io.netty.util.concurrent.EventExecutorGroup;
import io.netty.util.concurrent.GlobalEventExecutor;

import java.util.Map;

import javax.net.ssl.SSLException;

import static io.ballerina.stdlib.http.transport.contract.Constants.PIPELINING_THREAD_COUNT;
import static io.ballerina.stdlib.http.transport.contract.Constants.PIPELINING_THREAD_POOL_NAME;

/**
 * Implementation of HttpWsConnectorFactory interface.
 */
public class DefaultHttpWsConnectorFactory implements HttpWsConnectorFactory {

    private final EventLoopGroup bossGroup;
    private final EventLoopGroup workerGroup;
    private final EventLoopGroup clientGroup;
    private final NioEventLoopGroup group;
    private EventExecutorGroup pipeliningGroup;

    private final ChannelGroup allChannels = new DefaultChannelGroup(GlobalEventExecutor.INSTANCE);

    public DefaultHttpWsConnectorFactory() {
        bossGroup = new NioEventLoopGroup(Runtime.getRuntime().availableProcessors());
        workerGroup = new NioEventLoopGroup(Runtime.getRuntime().availableProcessors() * 2);
        clientGroup = new NioEventLoopGroup(Runtime.getRuntime().availableProcessors() * 2);
        group = new NioEventLoopGroup(Runtime.getRuntime().availableProcessors());
    }

    public DefaultHttpWsConnectorFactory(int serverSocketThreads, int childSocketThreads, int clientThreads) {
        bossGroup = new NioEventLoopGroup(serverSocketThreads);
        workerGroup = new NioEventLoopGroup(childSocketThreads);
        clientGroup = new NioEventLoopGroup(clientThreads);
        group = new NioEventLoopGroup(serverSocketThreads);

    }

    @Override
    public ServerConnector createServerConnector(ServerBootstrapConfiguration serverBootstrapConfiguration,
            ListenerConfiguration listenerConfig) {

        ServerConnectorBootstrap serverConnectorBootstrap;

        if("3.0".equals(listenerConfig.getVersion())){
            QuicSslContext sslctx = null;

            SSLConfig sslConfig = listenerConfig.getListenerSSLConfig();
            if (sslConfig != null) {
                sslctx = createHttp3SslContext(sslConfig);
            }

            serverConnectorBootstrap = new ServerConnectorBootstrap(allChannels,sslctx);
            serverConnectorBootstrap.addHttp3SocketConfiguration(serverBootstrapConfiguration);
            serverConnectorBootstrap.http3AddSecurity(sslConfig);

            serverConnectorBootstrap.http3AddIdleTimeout(listenerConfig.getSocketIdleTimeout());

            serverConnectorBootstrap.addHttp3ThreadPools(group);
            serverConnectorBootstrap.addHttp3KeepAliveBehaviour(listenerConfig.getKeepAliveConfig());

        }else{
            serverConnectorBootstrap = new ServerConnectorBootstrap(allChannels);
            serverConnectorBootstrap.addSocketConfiguration(serverBootstrapConfiguration);
            SSLConfig sslConfig = listenerConfig.getListenerSSLConfig();
            serverConnectorBootstrap.addSecurity(sslConfig);

            if (sslConfig != null) {
                setSslContext(serverConnectorBootstrap, sslConfig, listenerConfig);
            }
            serverConnectorBootstrap.addIdleTimeout(listenerConfig.getSocketIdleTimeout());

            if (Constants.HTTP_2_0.equals(listenerConfig.getVersion())) {
                serverConnectorBootstrap.setHttp2Enabled(true);
            }
            serverConnectorBootstrap.addHttpTraceLogHandler(listenerConfig.isHttpTraceLogEnabled());
            serverConnectorBootstrap.addHttpAccessLogHandler(listenerConfig.isHttpAccessLogEnabled());
            serverConnectorBootstrap.addThreadPools(bossGroup, workerGroup);
            serverConnectorBootstrap.addHeaderAndEntitySizeValidation(listenerConfig.getMsgSizeValidationConfig());
            serverConnectorBootstrap.addChunkingBehaviour(listenerConfig.getChunkConfig());
            serverConnectorBootstrap.addKeepAliveBehaviour(listenerConfig.getKeepAliveConfig());
            serverConnectorBootstrap.addServerHeader(listenerConfig.getServerHeader());

            serverConnectorBootstrap.setPipeliningEnabled(listenerConfig.isPipeliningEnabled());
            serverConnectorBootstrap.setWebSocketCompressionEnabled(listenerConfig.isWebSocketCompressionEnabled());
            serverConnectorBootstrap.setPipeliningLimit(listenerConfig.getPipeliningLimit());
        }
        if (listenerConfig.isPipeliningEnabled()) {
            pipeliningGroup = new DefaultEventExecutorGroup(PIPELINING_THREAD_COUNT, new DefaultThreadFactory(
                    PIPELINING_THREAD_POOL_NAME));
            if("3.0".equals(listenerConfig.getVersion())) { //changedd
                serverConnectorBootstrap.setHttp3PipeliningThreadGroup(pipeliningGroup);
            }else{
                serverConnectorBootstrap.setPipeliningThreadGroup(pipeliningGroup);
            }
        }
        return serverConnectorBootstrap.getServerConnector(listenerConfig.getHost(), listenerConfig.getPort(),listenerConfig.getVersion()); //changedd
    }

    private QuicSslContext createHttp3SslContext(SSLConfig sslConfig) {
        QuicSslContext sslContext;
        try {
            SSLHandlerFactory sslHandlerFactory = new SSLHandlerFactory(sslConfig);
            sslContext = sslHandlerFactory.createHttp3TLSContextForServer();

        } catch (SSLException e) {
            throw new RuntimeException("Failed to create ssl context from given certs and key", e);
        }
        return sslContext;

    }

    private void setSslContext(ServerConnectorBootstrap serverConnectorBootstrap, SSLConfig sslConfig,
            ListenerConfiguration listenerConfig) {
        try {
            SSLHandlerFactory sslHandlerFactory = new SSLHandlerFactory(sslConfig);
            serverConnectorBootstrap.addcertificateRevocationVerifier(sslConfig.isValidateCertEnabled());
            serverConnectorBootstrap.addCacheDelay(sslConfig.getCacheValidityPeriod());
            serverConnectorBootstrap.addCacheSize(sslConfig.getCacheSize());
            serverConnectorBootstrap.addOcspStapling(sslConfig.isOcspStaplingEnabled());
            serverConnectorBootstrap.addSslHandlerFactory(sslHandlerFactory);
            if (sslConfig.getKeyStore() != null) {
                if (Constants.HTTP_2_0.equals(listenerConfig.getVersion())) {
                    serverConnectorBootstrap
                            .addHttp2SslContext(sslHandlerFactory.createHttp2TLSContextForServer(sslConfig));
                } else {
                    serverConnectorBootstrap
                            .addKeystoreSslContext(sslHandlerFactory.createSSLContextFromKeystores(true));
                }
            } else {
                if (Constants.HTTP_2_0.equals(listenerConfig.getVersion())) {
                    serverConnectorBootstrap
                            .addHttp2SslContext(sslHandlerFactory.createHttp2TLSContextForServer(sslConfig));
                } else {
                    serverConnectorBootstrap.addCertAndKeySslContext(sslHandlerFactory.createHttpTLSContextForServer());
                }
            }
        } catch (SSLException e) {
            throw new RuntimeException("Failed to create ssl context from given certs and key", e);
        }
    }

    @Override
    public HttpClientConnector createHttpClientConnector(
            Map<String, Object> transportProperties, SenderConfiguration senderConfiguration) {
        BootstrapConfiguration bootstrapConfig = new BootstrapConfiguration(transportProperties);
        ConnectionManager connectionManager = new ConnectionManager(senderConfiguration.getPoolConfiguration());
        int configHashCode = Util.getIntProperty(transportProperties, HttpConstants.CLIENT_CONFIG_HASH_CODE, 0);
        return new DefaultHttpClientConnector(connectionManager, senderConfiguration, bootstrapConfig, clientGroup,
                                              configHashCode);
    }

    @Override
    public HttpClientConnector createHttpClientConnector(
        Map<String, Object> transportProperties, SenderConfiguration senderConfiguration,
        ConnectionManager connectionManager) {
        BootstrapConfiguration bootstrapConfig = new BootstrapConfiguration(transportProperties);
        int configHashCode = Util.getIntProperty(transportProperties, HttpConstants.CLIENT_CONFIG_HASH_CODE, 0);
        return new DefaultHttpClientConnector(connectionManager, senderConfiguration, bootstrapConfig, clientGroup,
                                              configHashCode);
    }

    @Override
    public WebSocketClientConnector createWsClientConnector(WebSocketClientConnectorConfig clientConnectorConfig) {
        return new DefaultWebSocketClientConnector(clientConnectorConfig, clientGroup);
    }

    @Override
    public void shutdown() throws InterruptedException {
        allChannels.close().sync();
        workerGroup.shutdownGracefully().sync();
        bossGroup.shutdownGracefully().sync();
        clientGroup.shutdownGracefully().sync();
        if (pipeliningGroup != null) {
            pipeliningGroup.shutdownGracefully().sync();
        }
    }

    /**
     * This method is for shutting down the connectors without a delay.
     **/
    public void shutdownNow() {
        allChannels.close();
        workerGroup.shutdownGracefully();
        bossGroup.shutdownGracefully();
        clientGroup.shutdownGracefully();
        if (pipeliningGroup != null) {
            pipeliningGroup.shutdownGracefully();
        }
    }
}
