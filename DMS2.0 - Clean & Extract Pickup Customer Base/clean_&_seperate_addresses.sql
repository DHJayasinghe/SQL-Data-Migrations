--DELETE FROM dbo.__MigrationPickupAddresses
--INSERT INTO dbo.__MigrationPickupAddresses(PickupId,CustomerId,CustomerName,OriginalAddress,ClearedAddress,City)
SELECT
	P.PICKUP_ID PickupId,
	P.CUSTOMER_ID CustomerId,
	UPPER(C.CUSTOMER_NAME) CustomerName,
	CASE WHEN P.PICKUP_ADDRESS IS NULL THEN C.[ADDRESS] ELSE P.PICKUP_ADDRESS END Original_Address,
	(SELECT UPPER(STRING_AGG(T2.value,' ')) AS [Address] 
		FROM STRING_SPLIT((	
				SELECT REPLACE(
					--REPLACE(
					REPLACE(REPLACE(REPLACE(REPLACE(STRING_AGG(TRIM(REPLACE(REPLACE(T1.value,'SRI LANKA',''),'SRILANKA','')), ', ')
					,char(13), ' '),char(10), ' '), char(9), ' '),':',' ')
					--,'.','')
					,'_','/') AS [Address] --replace unnecessary tab spaces, line breaks(CR, LF CR+LF) with a space, colons, dots and replace underscore with forward slashes
				From STRING_SPLIT(CASE WHEN P.PICKUP_ADDRESS IS NULL THEN C.[ADDRESS] ELSE P.PICKUP_ADDRESS END,',') T1 --Split string by comma and concat words again with with a value
				WHERE TRIM(T1.value)!=''),' ') T2  --Split string by space and concat words again with with a value
		WHERE TRIM(T2.value)!='') [Cleared_Address],
	(SELECT UPPER(STRING_AGG(T2.value,' ')) AS [Address] 
		FROM STRING_SPLIT((	
				SELECT REPLACE(
					--REPLACE(
					REPLACE(REPLACE(REPLACE(REPLACE(STRING_AGG(TRIM(T1.value), ', ')
					,char(13), ' '),char(10), ' '), char(9), ' '),':','')
					--,'.','')
					,'_','/') AS [City] --replace unnecessary tab spaces, line breaks(CR, LF CR+LF) with a space, colons, dots and replace underscore with forward slashes
				From STRING_SPLIT(CASE WHEN P.PICKUP_TOWN IS NULL THEN C.TOWN ELSE P.PICKUP_TOWN END,',') T1 --Split string by comma and concat words again with with a value
				WHERE TRIM(T1.value)!=''),' ') T2  --Split string by space and concat words again with with a value
		WHERE TRIM(T2.value)!='') [City],
		C.CONTACTS Contacts
INTO #tmpPickupAddresses
FROM dbo.PICKUP P LEFT JOIN [dbo].[CUSTOMER] C
ON P.CUSTOMER_ID=C.CUSTOMER_ID

SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	CASE 
		WHEN PATINDEX('%COL %',Cleared_Address)>0 THEN STUFF(Cleared_Address,PATINDEX('%COL %',Cleared_Address),3,'COLOMBO')
		WHEN PATINDEX('%CO %',Cleared_Address)>0 THEN STUFF(Cleared_Address,PATINDEX('%CO %',Cleared_Address),3,'COLOMBO') 
		ELSE Cleared_Address END  Cleared_Address, --replace COL like keywords with COLOMBO
	City,
	Contacts
INTO #tmpPickupAddresses2
FROM #tmpPickupAddresses
DROP TABLE #tmpPickupAddresses --delete first temp table to release memory

SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	CASE WHEN CHARINDEX(REVERSE(City),REVERSE(Cleared_Address))>0 THEN REVERSE(TRIM(SUBSTRING(REVERSE(Cleared_Address),CHARINDEX(REVERSE(City),REVERSE(Cleared_Address)),LEN(Cleared_Address)))) ELSE Cleared_Address END Cleared_Address, -- seperate contact details after city name on address field (REVERSE to search from end)
	CASE WHEN CHARINDEX(REVERSE(City),REVERSE(Cleared_Address))>0 THEN REVERSE(TRIM(REPLACE(SUBSTRING(REVERSE(Cleared_Address),0,CHARINDEX(REVERSE(City),REVERSE(Cleared_Address))),City,''))) ELSE '' END Filtered_Contact,
	City,
	Contacts
INTO #tmpPickupAddresses3
FROM #tmpPickupAddresses2
DROP TABLE #tmpPickupAddresses2

;WITH STEP1 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	CONCAT(Cleared_Address, CASE WHEN LEN(Filtered_Contact)<=2 AND ISNUMERIC(Filtered_Contact)=1 THEN (' ' + Filtered_Contact) ELSE '' END) Cleared_Address, --to transfer COLOMBO 03 like single char prefix back to the Address field while removing from contact field
	CASE WHEN LEN(Filtered_Contact)<=2 AND ISNUMERIC(TRIM(Filtered_Contact))=1 THEN '' ELSE TRIM(Filtered_Contact) END Filtered_Contact,
	City,
	Contacts
FROM #tmpPickupAddresses3),
STEP2 AS
(SELECT
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	CASE 
		WHEN REPLACE(REPLACE(REPLACE(REPLACE(Filtered_Contact,'(',''),')',''),',',''),'.','') IN ('ROAD','RD','AVE','IPZ','AVENUE','NORTH','CENTRAL HOSPITAL','ZONE','WAREHOUSE','NORTH','SOUTH','WEST','FORT') OR (LEN(Filtered_Contact)<9 AND ISNUMERIC(Filtered_Contact)=1) THEN CONCAT(Cleared_Address,' ',Filtered_Contact) --move road, avenue like prefix back to address fields while removing from contact field
		WHEN LEN(REPLACE(REPLACE(Filtered_Contact,',',''),'.',''))<=3 THEN CONCAT(Cleared_Address,'',Filtered_Contact) 
		ELSE Cleared_Address 
	END Cleared_Address,
	CASE 
		WHEN REPLACE(REPLACE(REPLACE(REPLACE(Filtered_Contact,'(',''),')',''),',',''),'.','') IN ('ROAD','RD','AVE','IPZ','AVENUE','NORTH','CENTRAL HOSPITAL','ZONE','WAREHOUSE','NORTH','SOUTH','WEST','FORT') OR (LEN(Filtered_Contact)<9 AND ISNUMERIC(Filtered_Contact)=1) THEN ''
		WHEN LEN(REPLACE(REPLACE(Filtered_Contact,',',''),'.',''))<=3 THEN '' 
		ELSE Filtered_Contact
	END Filtered_Contact,
	City,
	Contacts
FROM STEP1
WHERE LEN(Filtered_Contact)>0),
STEP3 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	REPLACE(REPLACE(REPLACE(REPLACE(Filtered_Contact,'(',''),')',''),',',''),'.','') Cleared_Contact, -- seperated contact details without unwanted characters
	Filtered_Contact,
	City,
	Contacts
FROM STEP2)
SELECT
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	STUFF(
		STUFF(Cleared_Contact,PATINDEX('%[0-9] [0-9]%',Cleared_Contact)+1,IIF(PATINDEX('%[0-9] [0-9]%',Cleared_Contact)>0,1,0),''),
		PATINDEX('%[0-9] [0-9]%',STUFF(Cleared_Contact,PATINDEX('%[0-9] [0-9]%',Cleared_Contact)+1,IIF(PATINDEX('%[0-9] [0-9]%',Cleared_Contact)>0,1,0),''))+1,
		IIF(PATINDEX('%[0-9] [0-9]%',STUFF(Cleared_Contact,PATINDEX('%[0-9] [0-9]%',Cleared_Contact)+1,IIF(PATINDEX('%[0-9] [0-9]%',Cleared_Contact)>0,1,0),''))>0,1,0),'') Cleared_Contact, --clear phone numberes with spaces
	Filtered_Contact,
	City,
	Contacts
INTO #tmpPickupAddresses4
FROM STEP3
DROP TABLE #tmpPickupAddresses3

;WITH STEP4 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Cleared_Contact,
	(SELECT COUNT(value) FROM STRING_SPLIT(Cleared_Contact,' ') WHERE TRIM(value) NOT IN ('',',','.','&','-','/')) NoOfWords,
	(SELECT COUNT(value) FROM STRING_SPLIT(Cleared_Contact,' ') 
		WHERE TRIM(value) NOT IN ('',',','.','&','-') 
		AND (TRIM(value) IN ('LOT''BLOCK','INDUSTRIAL','ZONE','BUILDING','FLOOR','HOUSE','DEPARTMENT','APARTMENT','FACTORY','FACTRY','ROAD','LANE','NORTH','SOUTH','WEST','NEW','TOWN','TOWER','CENTRAL','HOSPITAL','DIVISION','IMPORTS','EXPORTS','GARDINER','MAWATHA','EPZ','TRADE','PORUWADANDA','BORALUGODA','DEPARTMENT','AVIASSAWELLA','MINUWANGODA','PANOLUWA','TORAKOLAYAYA','MALVANA','PITTIYAGODA') --if contains this keywords
		OR (ISNUMERIC(value)=1 AND LEN(value)<=2) OR (LEN(value)<=3 AND PATINDEX('%[0-9]TH%',value)>0) --if contains keywords like 4th
		OR TRIM(value) IN (SELECT Distinct City From #tmpPickupAddresses4)) --if contains city word
	) NoOfPrefixWords,  
	Filtered_Contact,
	City,
	Contacts
FROM #tmpPickupAddresses4)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	--Cleared_Contact Cleared_Contact_Before,
	--NoOfWords,
	--NoOfPrefixWords,
	CASE WHEN 
		CASE NoOfWords WHEN 1 THEN 1 ELSE ROUND(CONVERT(decimal(8,0),CONVERT(decimal(8,1),NoOfWords)/2),0) END <= NoOfPrefixWords  -- if NoOfWords = 1 not divided by 2 
	THEN Filtered_Contact ELSE NULL END Seperated_Addr_Prefix, --if most number of words contains above keywords -> not contain contact details
	CASE WHEN 
		CASE NoOfWords WHEN 1 THEN 1 ELSE ROUND(CONVERT(decimal(8,0),CONVERT(decimal(8,1),NoOfWords)/2),0) END <= NoOfPrefixWords
	THEN NULL ELSE Filtered_Contact END Cleared_Contact,
	City,
	Contacts
FROM STEP4

--'GENERAL ENGINEERING & BUSINESS SERVICES (PTE) LTD CARE OF PLATINUM LOGISTICS NO. 171, NAWALA ROAD'
--DROP TABLE #tmpPickupAddresses4





