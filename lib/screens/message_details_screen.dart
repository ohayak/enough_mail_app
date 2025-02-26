import 'dart:async';
import 'dart:ui';

import 'package:enough_mail/enough_mail.dart';
import 'package:enough_mail_app/locator.dart';
import 'package:enough_mail_app/models/compose_data.dart';
import 'package:enough_mail_app/models/message.dart';
import 'package:enough_mail_app/models/message_source.dart';
import 'package:enough_mail_app/models/settings.dart';
import 'package:enough_mail_app/routes.dart';
import 'package:enough_mail_app/screens/base.dart';
import 'package:enough_mail_app/services/icon_service.dart';
import 'package:enough_mail_app/services/i18n_service.dart';
import 'package:enough_mail_app/services/mail_service.dart';
import 'package:enough_mail_app/services/navigation_service.dart';
import 'package:enough_mail_app/services/notification_service.dart';
import 'package:enough_mail_app/services/settings_service.dart';
import 'package:enough_mail_app/util/localized_dialog_helper.dart';
import 'package:enough_mail_app/widgets/attachment_chip.dart';
import 'package:enough_mail_app/widgets/button_text.dart';
import 'package:enough_mail_app/widgets/expansion_wrap.dart';
import 'package:enough_mail_app/widgets/ical_interactive_media.dart';
import 'package:enough_mail_app/widgets/mail_address_chip.dart';
import 'package:enough_mail_app/widgets/message_actions.dart';
import 'package:enough_mail_app/widgets/message_overview_content.dart';
import 'package:enough_mail_app/widgets/inherited_widgets.dart';
import 'package:enough_mail_flutter/enough_mail_flutter.dart';
import 'package:enough_media/enough_media.dart';
import 'package:enough_platform_widgets/enough_platform_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class MessageDetailsScreen extends StatefulWidget {
  final Message message;
  const MessageDetailsScreen({Key? key, required this.message})
      : super(key: key);

  @override
  _DetailsScreenState createState() => _DetailsScreenState();
}

enum _OverflowMenuChoice { showContents, showSourceCode }

class _DetailsScreenState extends State<MessageDetailsScreen> {
  PageController? _pageController;
  late MessageSource _source;
  Message? _current;

  @override
  void initState() {
    _pageController = PageController(initialPage: widget.message.sourceIndex);
    _current = widget.message;
    _source = _current!.source;
    super.initState();
  }

  @override
  void dispose() {
    _pageController!.dispose();
    super.dispose();
  }

  Message? _getMessage(int index) {
    if (_current!.sourceIndex == index) {
      return _current;
    }
    _current = _source.getMessageAt(index);
    return _current;
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      itemCount: _source.size,
      itemBuilder: (context, index) => _MessageContent(_getMessage(index)!),
    );
  }
}

class _MessageContent extends StatefulWidget {
  final Message message;
  const _MessageContent(this.message, {Key? key}) : super(key: key);

  @override
  _MessageContentState createState() => _MessageContentState();
}

class _MessageContentState extends State<_MessageContent> {
  late bool _blockExternalImages;
  late bool _messageDownloadError;
  bool _messageRequiresRefresh = false;
  bool _isWebViewZoomedOut = false;
  Object? errorObject;
  StackTrace? errorStackTrace;

  @override
  void initState() {
    final mime = widget.message.mimeMessage;
    if (mime != null && mime.isDownloaded) {
      _blockExternalImages = _shouldImagesBeBlocked(mime);
    } else {
      _messageRequiresRefresh = mime?.envelope == null;
      _blockExternalImages = false;
    }
    _messageDownloadError = false;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Base.buildAppChrome(
      context,
      title: widget.message.mimeMessage!.decodeSubject() ??
          localizations.subjectUndefined,
      content: MessageWidget(
        message: widget.message,
        child: _buildMailDetails(localizations),
      ),
      appBarActions: [
        //PlatformIconButton(icon: Icon(Icons.reply), onPressed: reply),
        PlatformPopupMenuButton<_OverflowMenuChoice>(
          onSelected: (_OverflowMenuChoice result) {
            switch (result) {
              case _OverflowMenuChoice.showContents:
                locator<NavigationService>()
                    .push(Routes.mailContents, arguments: widget.message);
                break;
              case _OverflowMenuChoice.showSourceCode:
                _showSourceCode();
                break;
            }
          },
          itemBuilder: (BuildContext context) => [
            PlatformPopupMenuItem<_OverflowMenuChoice>(
              value: _OverflowMenuChoice.showContents,
              child: Text(localizations.viewContentsAction),
            ),
            if (locator<SettingsService>().settings.enableDeveloperMode) ...{
              PlatformPopupMenuItem<_OverflowMenuChoice>(
                value: _OverflowMenuChoice.showSourceCode,
                child: Text(localizations.viewSourceAction),
              ),
            },
          ],
        ),
      ],
      bottom: MessageActions(message: widget.message),
    );
  }

  Widget _buildMailDetails(AppLocalizations localizations) {
    return SingleChildScrollView(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildHeader(localizations),
            ),
            _buildContent(localizations),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations localizations) {
    final mime = widget.message.mimeMessage!;
    final attachments = widget.message.attachments;
    final date = locator<I18nService>().formatDateTime(mime.decodeDate());
    final subject = mime.decodeSubject();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            columnWidths: {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth()
            },
            children: [
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                  child: Text(localizations.detailsHeaderFrom),
                ),
                _buildMailAddresses(mime.from)
              ]),
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                  child: Text(localizations.detailsHeaderTo),
                ),
                _buildMailAddresses(mime.to)
              ]),
              if (mime.cc?.isNotEmpty ?? false) ...{
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                    child: Text(localizations.detailsHeaderCc),
                  ),
                  _buildMailAddresses(mime.cc)
                ]),
              },
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                  child: Text(localizations.detailsHeaderDate),
                ),
                Text(date),
              ]),
            ]),
        SelectableText(
          subject ?? localizations.subjectUndefined,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        _buildAttachments(attachments),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Divider(height: 2),
        ),
        if (_blockExternalImages ||
            mime.isNewsletter ||
            mime.threadSequence != null ||
            _isWebViewZoomedOut) ...{
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (mime.threadSequence != null) ...{
                ThreadSequenceButton(message: widget.message),
              } else ...{
                Container(),
              },
              if (_isWebViewZoomedOut) ...{
                PlatformIconButton(
                  icon: Icon(Icons.zoom_in),
                  onPressed: () {
                    locator<NavigationService>()
                        .push(Routes.mailContents, arguments: widget.message);
                  },
                ),
              } else ...{
                Container(),
              },
              if (_blockExternalImages) ...{
                PlatformElevatedButton(
                  child: ButtonText(localizations.detailsActionShowImages),
                  onPressed: () => setState(() {
                    _blockExternalImages = false;
                  }),
                ),
              } else ...{
                Container(),
              },
              if (mime.isNewsletter) ...{
                UnsubscribeButton(
                  message: widget.message,
                ),
              } else ...{
                Container(),
              },
            ],
          ),
        },
        if (ReadReceiptButton.shouldBeShown(mime)) ...{
          ReadReceiptButton(),
        }
      ],
    );
  }

  Widget _buildMailAddresses(List<MailAddress>? addresses) {
    if (addresses?.isEmpty ?? true) {
      return Container();
    }
    return MailAddressList(mailAddresses: addresses!);
  }

  Widget _buildAttachments(List<ContentInfo> attachments) {
    return Wrap(
      children: [
        for (var attachment in attachments) ...{
          AttachmentChip(info: attachment, message: widget.message)
        }
      ],
    );
  }

  Widget _buildContent(AppLocalizations localizations) {
    if (_messageDownloadError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(localizations.detailsErrorDownloadInfo),
          ),
          TextButton.icon(
            icon: Icon(Icons.refresh),
            label: ButtonText(localizations.detailsErrorDownloadRetry),
            onPressed: () {
              setState(() {
                _messageDownloadError = false;
              });
            },
          ),
          if (locator<SettingsService>().settings.enableDeveloperMode) ...{
            Text('Details:'),
            Text(errorObject?.toString() ?? '<unknown error>'),
            Text(errorStackTrace?.toString() ?? '<no stacktrace>'),
            TextButton.icon(
              icon: Icon(Icons.copy),
              label: ButtonText('Copy to clipboard'),
              onPressed: () {
                final text = errorObject?.toString() ??
                    '<unknown error>' +
                        '\n\n' +
                        (errorStackTrace?.toString() ?? '<no stacktrace>');
                final data = ClipboardData(text: text);
                Clipboard.setData(data);
              },
            ),
          },
        ],
      );
    }

    return MimeMessageDownloader(
      mimeMessage: widget.message.mimeMessage!,
      mailClient: widget.message.mailClient,
      markAsSeen: true,
      onDownloaded: _onMimeMessageDownloaded,
      onError: _onMimeMessageError,
      blockExternalImages: _blockExternalImages,
      mailtoDelegate: _handleMailto,
      maxImageWidth: 320,
      showMediaDelegate: _navigateToMedia,
      includedInlineTypes: [MediaToptype.image],
      onZoomed: (controller, factor) {
        if (factor < 0.9) {
          setState(() {
            _isWebViewZoomedOut = true;
          });
        }
      },
      builder: (context, mimeMessage) {
        final textCalendarPart =
            mimeMessage.getAlternativePart(MediaSubtype.textCalendar);
        if (textCalendarPart != null) {
          // || mediaType.sub == MediaSubtype.applicationIcs)
          final calendarText = textCalendarPart.decodeContentText();
          if (calendarText != null) {
            final mediaProvider =
                TextMediaProvider('invite.ics', 'text/calendar', calendarText);
            return IcalInteractiveMedia(
                mediaProvider: mediaProvider, message: widget.message);
          }
        }
        return null;
      },
    );
  }

  bool _shouldImagesBeBlocked(MimeMessage mimeMessage) {
    var blockExternalImages =
        locator<SettingsService>().settings.blockExternalImages ||
            widget.message.source.shouldBlockImages;
    if (blockExternalImages) {
      final html = mimeMessage.decodeTextHtmlPart();
      final hasImages = (html != null) && (html.contains('<img '));
      if (!hasImages) {
        blockExternalImages = false;
      }
    }
    return blockExternalImages;
  }

  // Update view after message has been downloaded successfully
  void _onMimeMessageDownloaded(MimeMessage mimeMessage) {
    widget.message.updateMime(mimeMessage);
    final blockExternalImages = _shouldImagesBeBlocked(mimeMessage);
    if (mounted &&
        (_messageRequiresRefresh ||
            mimeMessage.isSeen ||
            mimeMessage.isNewsletter ||
            mimeMessage.hasAttachments() ||
            blockExternalImages)) {
      setState(() {
        _blockExternalImages = blockExternalImages;
      });
    }
    locator<NotificationService>()
        .cancelNotificationForMailMessage(widget.message);
  }

  void _onMimeMessageError(Object? e, StackTrace? s) {
    if (mounted) {
      setState(() {
        errorObject = e;
        errorStackTrace = s;
        _messageDownloadError = true;
      });
    }
  }

  Future _handleMailto(Uri mailto, MimeMessage mimeMessage) {
    final messageBuilder = locator<MailService>().mailto(mailto, mimeMessage);
    final composeData =
        ComposeData([widget.message], messageBuilder, ComposeAction.newMessage);
    return locator<NavigationService>()
        .push(Routes.mailCompose, arguments: composeData);
  }

  Future _navigateToMedia(InteractiveMediaWidget mediaWidget) async {
    return locator<NavigationService>()
        .push(Routes.interactiveMedia, arguments: mediaWidget);
  }

  void _showSourceCode() {
    locator<NavigationService>()
        .push(Routes.sourceCode, arguments: widget.message.mimeMessage);
  }

  // void _next() {
  //   _navigateToMessage(widget.message.next);
  // }

  // void _previous() {
  //   _navigateToMessage(widget.message.previous);
  // }

  // void _navigateToMessage(Message? message) {
  //   if (message != null) {
  //     locator<NavigationService>()
  //         .push(Routes.mailDetails, arguments: message, replace: true);
  //   }
  // }
}

class MessageContentsScreen extends StatelessWidget {
  final Message message;
  const MessageContentsScreen({Key? key, required this.message})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Base.buildAppChrome(
      context,
      title: message.mimeMessage?.decodeSubject() ??
          AppLocalizations.of(context)!.subjectUndefined,
      content: SafeArea(
        child: MimeMessageViewer(
          mimeMessage: message.mimeMessage!,
          adjustHeight: false,
          mailtoDelegate: _handleMailto,
          showMediaDelegate: _navigateToMedia,
        ),
      ),
    );
  }

  Future _handleMailto(Uri mailto, MimeMessage mimeMessage) {
    final messageBuilder = locator<MailService>().mailto(mailto, mimeMessage);
    final composeData =
        ComposeData([message], messageBuilder, ComposeAction.newMessage);
    return locator<NavigationService>()
        .push(Routes.mailCompose, arguments: composeData);
  }

  Future _navigateToMedia(InteractiveMediaWidget mediaWidget) {
    return locator<NavigationService>()
        .push(Routes.interactiveMedia, arguments: mediaWidget);
  }
}

class ThreadSequenceButton extends StatefulWidget {
  final Message message;
  ThreadSequenceButton({Key? key, required this.message}) : super(key: key);

  @override
  _ThreadSequenceButtonState createState() => _ThreadSequenceButtonState();
}

class _ThreadSequenceButtonState extends State<ThreadSequenceButton> {
  OverlayEntry? _overlayEntry;
  late Future<List<Message>> _loadingFuture;

  @override
  void dispose() {
    if (_overlayEntry != null) {
      _removeOverlay();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadingFuture = _loadMessages();
  }

  Future<List<Message>> _loadMessages() async {
    final existingSource = widget.message.source;
    if (existingSource is ListMessageSource) {
      return existingSource.messages!;
    }
    final mailClient = widget.message.mailClient;
    final mimeMessages = await mailClient.fetchMessageSequence(
        widget.message.mimeMessage!.threadSequence!,
        fetchPreference: FetchPreference.envelope);
    final source = ListMessageSource(widget.message.source);
    final messages = <Message>[];
    for (var i = 0; i < mimeMessages.length; i++) {
      final mime = mimeMessages[i];
      final message = Message(mime, mailClient, source, i);
      messages.add(message);
    }
    source.messages = messages.reversed.toList();
    return source.messages!;
  }

  @override
  Widget build(BuildContext context) {
    final length = widget.message.mimeMessage!.threadSequence?.length ?? 0;
    return WillPopScope(
      onWillPop: () {
        if (_overlayEntry == null) {
          return Future.value(true);
        }
        _removeOverlay();
        return Future.value(false);
      },
      child: PlatformIconButton(
        icon: IconService.buildNumericIcon(length),
        onPressed: () {
          if (_overlayEntry != null) {
            _removeOverlay();
          } else {
            _overlayEntry = _buildThreadsOverlay();
            Overlay.of(context)!.insert(_overlayEntry!);
          }
        },
      ),
    );
  }

  void _removeOverlay() {
    _overlayEntry!.remove();
    _overlayEntry = null;
  }

  void _select(Message message) {
    _removeOverlay();
    locator<NavigationService>()
        .push(Routes.mailDetails, arguments: message, replace: false);
  }

  OverlayEntry _buildThreadsOverlay() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final renderSize = renderBox.size;
    final size = MediaQuery.of(context).size;
    final currentUid = widget.message.mimeMessage!.uid;
    final top = offset.dy + renderSize.height + 5.0;
    final height = size.height - top - 16;

    return OverlayEntry(
      builder: (context) => GestureDetector(
        onTap: () {
          _removeOverlay();
        },
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Color(0x09000000))),
            Positioned(
              left: offset.dx,
              top: top,
              width: size.width - offset.dx - 16,
              child: Material(
                elevation: 4.0,
                child: FutureBuilder<List<Message>?>(
                  future: _loadingFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return PlatformProgressIndicator();
                    }
                    final messages = snapshot.data!;
                    final isSentFolder = widget.message.source.isSent;
                    return ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: height),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: messages
                            .map((message) => PlatformListTile(
                                  title: MessageOverviewContent(
                                    message: message,
                                    isSentMessage: isSentFolder,
                                  ),
                                  onTap: () => _select(message),
                                  selected:
                                      (message.mimeMessage!.uid == currentUid),
                                ))
                            .toList(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReadReceiptButton extends StatefulWidget {
  ReadReceiptButton({Key? key}) : super(key: key);

  @override
  _ReadReceiptButtonState createState() => _ReadReceiptButtonState();

  static bool shouldBeShown(MimeMessage mime) =>
      (mime.isReadReceiptSent || mime.isReadReceiptRequested) &&
      (locator<SettingsService>().settings.readReceiptDisplaySetting !=
          ReadReceiptDisplaySetting.never);
}

class _ReadReceiptButtonState extends State<ReadReceiptButton> {
  bool _isSendingReadReceipt = false;

  @override
  Widget build(BuildContext context) {
    final message = Message.of(context)!;
    final mime = message.mimeMessage!;
    final localizations = AppLocalizations.of(context)!;
    if (mime.isReadReceiptSent) {
      return Text(localizations.detailsReadReceiptSentStatus,
          style: Theme.of(context).textTheme.caption);
    } else if (_isSendingReadReceipt) {
      return PlatformProgressIndicator();
    } else {
      return ElevatedButton(
        child: ButtonText(localizations.detailsSendReadReceiptAction),
        onPressed: () async {
          setState(() {
            _isSendingReadReceipt = true;
          });
          final readReceipt = MessageBuilder.buildReadReceipt(
            mime,
            message.account.fromAddress,
            reportingUa: 'Maily 1.0',
            subject: localizations.detailsReadReceiptSubject,
          );
          await message.mailClient
              .sendMessage(readReceipt, appendToSent: false);
          await message.mailClient.flagMessage(mime, isReadReceiptSent: true);
          setState(() {
            _isSendingReadReceipt = false;
          });
        },
      );
    }
  }
}

class UnsubscribeButton extends StatefulWidget {
  final Message message;
  UnsubscribeButton({Key? key, required this.message}) : super(key: key);

  @override
  _UnsubscribeButtonState createState() => _UnsubscribeButtonState();
}

class _UnsubscribeButtonState extends State<UnsubscribeButton> {
  bool _isActive = false;

  @override
  Widget build(BuildContext context) {
    if (_isActive) {
      return PlatformProgressIndicator();
    }
    final localizations = AppLocalizations.of(context)!;
    if (widget.message.isNewsletterUnsubscribed) {
      return widget.message.isNewsLetterSubscribable
          ? PlatformElevatedButton(
              child:
                  ButtonText(localizations.detailsNewsletterActionResubscribe),
              onPressed: _resubscribe,
            )
          : Text(
              localizations.detailsNewsletterStatusUnsubscribed,
              style: TextStyle(fontStyle: FontStyle.italic),
            );
    } else {
      return PlatformElevatedButton(
        child: ButtonText(localizations.detailsNewsletterActionUnsubscribe),
        onPressed: _unsubscribe,
      );
    }
  }

  void _resubscribe() async {
    final localizations = AppLocalizations.of(context)!;
    final mime = widget.message.mimeMessage!;
    final listName = mime.decodeListName()!;
    final confirmation = await LocalizedDialogHelper.askForConfirmation(context,
        title: localizations.detailsNewsletterResubscribeDialogTitle,
        action: localizations.detailsNewsletterResubscribeDialogAction,
        query:
            localizations.detailsNewsletterResubscribeDialogQuestion(listName));
    if (confirmation == true) {
      setState(() {
        _isActive = true;
      });
      final mailClient = widget.message.mailClient;
      final subscribed = await mime.subscribe(mailClient);
      setState(() {
        _isActive = false;
      });
      if (subscribed) {
        setState(() {
          widget.message.isNewsletterUnsubscribed = false;
        });
        //TODO store flag only when server/mailbox supports abritrary flags?
        await mailClient.store(MessageSequence.fromMessage(mime),
            [Message.keywordFlagUnsubscribed],
            action: StoreAction.remove);
      }
      await LocalizedDialogHelper.showTextDialog(
          context,
          subscribed
              ? localizations.detailsNewsletterResubscribeSuccessTitle
              : localizations.detailsNewsletterResubscribeFailureTitle,
          subscribed
              ? localizations
                  .detailsNewsletterResubscribeSuccessMessage(listName)
              : localizations
                  .detailsNewsletterResubscribeFailureMessage(listName));
    }
  }

  void _unsubscribe() async {
    final localizations = AppLocalizations.of(context)!;
    final mime = widget.message.mimeMessage!;
    final listName = mime.decodeListName()!;
    final confirmation = await LocalizedDialogHelper.askForConfirmation(
      context,
      title: localizations.detailsNewsletterUnsubscribeDialogTitle,
      action: localizations.detailsNewsletterUnsubscribeDialogAction,
      query: localizations.detailsNewsletterUnsubscribeDialogQuestion(listName),
    );
    if (confirmation == true) {
      setState(() {
        _isActive = true;
      });
      final mailClient = widget.message.mailClient;
      var unsubscribed = false;
      try {
        unsubscribed = await mime.unsubscribe(mailClient);
      } catch (e, s) {
        print('error during unsubscribe: $e $s');
      }
      setState(() {
        _isActive = false;
      });
      if (unsubscribed) {
        setState(() {
          widget.message.isNewsletterUnsubscribed = true;
        });
        //TODO store flag only when server/mailbox supports abritrary flags?
        try {
          await mailClient.store(MessageSequence.fromMessage(mime),
              [Message.keywordFlagUnsubscribed],
              action: StoreAction.add);
        } catch (e, s) {
          print('error during unsubscribe flag store operation: $e $s');
        }
      }
      await LocalizedDialogHelper.showTextDialog(
          context,
          unsubscribed
              ? localizations.detailsNewsletterUnsubscribeSuccessTitle
              : localizations.detailsNewsletterUnsubscribeFailureTitle,
          unsubscribed
              ? localizations
                  .detailsNewsletterUnsubscribeSuccessMessage(listName)
              : localizations
                  .detailsNewsletterUnsubscribeFailureMessage(listName));
    }
  }
}

class MailAddressList extends StatefulWidget {
  const MailAddressList({Key? key, required this.mailAddresses})
      : super(key: key);
  final List<MailAddress> mailAddresses;

  @override
  _MailAddressListState createState() => _MailAddressListState();
}

class _MailAddressListState extends State<MailAddressList> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return ExpansionWrap(
      spacing: 4.0,
      runSpacing: 0.0,
      children: [
        for (var address in widget.mailAddresses) ...{
          MailAddressChip(mailAddress: address)
        }
      ],
      expandIndicator: DensePlatformIconButton(
        icon: Icon(Icons.keyboard_arrow_down),
        onPressed: () {
          setState(() {
            _isExpanded = true;
          });
        },
      ),
      compressIndicator: DensePlatformIconButton(
        icon: Icon(Icons.keyboard_arrow_up),
        onPressed: () {
          setState(() {
            _isExpanded = false;
          });
        },
      ),
      isExpanded: _isExpanded,
      maxRuns: 2,
    );
  }
}
