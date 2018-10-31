#!/bin/bash
echo Hello World
apt-get install unzip
pwd
ls -lt
wget "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" && unzip awscli-bundle.zip && ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws	

#CONFIGURING LOCAL VARIABLES FROM CONFIG.YML
template_file=`grep template_file ci/config.yml | sed 's/template_file: *//;s/ *\"//;s/\".*//;'`;
timestamp=`echo $(($(date +%s%N)/1000000))`
account=`grep accountId ci/config.yml | sed 's/accountId: *//;s/ *\"//;s/\".*//;'`;
region=`grep region ci/config.yml | sed 's/region: *//;s/ *\"//;s/\".*//;'`;
cross_account_role=`grep cross_account_role ci/config.yml | sed 's/cross_account_role: *//;s/ *\"//;s/\".*//;'`;
cross_account_role=`echo $cross_account_role | tr -d '\\040\\011\\012\\015'`
template=`echo $template_file | tr -d '\\040\\011\\012\\015'`
accountId=`echo $account | tr -d '\\040\\011\\012\\015'`
stack_name=`echo stack-$accountId-$template | cut -f1 -d'.'`
region=`echo $region | tr -d '\\040\\011\\012\\015'`
export AWS_DEFAULT_REGION=$1
export AWS_CONTAINER_CREDENTIALS_RELATIVE_URI=$2	
export output_bucket=$3
export sns_topic=$4

#ASSUMING ROLE FOR CROSS ACCOUNT STACK DEPLOYMENT
aws sts assume-role --role-arn $cross_account_role --role-session-name ${stack_name} > /usr/local/assume-role-output.txt

AccessKeyId=`grep AccessKeyId /usr/local/assume-role-output.txt | sed 's/"AccessKeyId": *//;s/ *\"//;s/\".*//;'`;
SecretAccessKey=`grep SecretAccessKey /usr/local/assume-role-output.txt | sed 's/"SecretAccessKey": *//;s/ *\"//;s/\".*//;'`;
SessionToken=`grep SessionToken /usr/local/assume-role-output.txt | sed 's/"SessionToken": *//;s/ *\"//;s/\".*//;'`;

#AWS CONFIGURE
export AWS_ACCESS_KEY_ID=$AccessKeyId
export AWS_SECRET_ACCESS_KEY=$SecretAccessKey
export AWS_SESSION_TOKEN=$SessionToken

#CREATION/UPDATION OF STACK IN ACCOUNT
if ! aws cloudformation describe-stacks --region $region --stack-name $stack_name ; then

  echo -e "\nStack does not exist, creating ..."
  aws cloudformation create-stack \
    --region $region \
    --stack-name $stack_name \
    --template-body file://templates/${template} \
    --capabilities CAPABILITY_IAM \
    --on-failure DELETE 
       > /usr/local/message-${stack_name}.txt

  echo "Waiting for stack to be created ..."
  aws cloudformation wait stack-create-complete \
    --region $region \
    --stack-name $stack_name \

  # Check if create-stack failed, rollbacked and deleted.
  if ! aws cloudformation describe-stacks --region $region --stack-name $stack_name ; then
    echo -e "\nError in stack create - Deleting stack" 	> /usr/local/output-${stack_name}.txt
    exit 1
  fi
  stack_create_update=true

else

  echo -e "\nStack exists, attempting update ..."

  set +e
  update_output=$( aws cloudformation update-stack \
    --region $region \
    --stack-name $stack_name \
    --template-body file://templates/${template} \
    --capabilities CAPABILITY_IAM \
      2>&1)
  up_status=$?
  set -e

  # Don't fail for no-update
  if [[ $up_status -ne 0 && $update_output == *"ValidationError"* && $update_output == *"No updates"* ]] ; then
      echo -e "\nFinished create/update - Stack already exists. No changes detected. Hence, no updates performed" > /usr/local/output-${stack_name}.txt
  else
    # If there is not any error in update
    echo "$update_output" >> /usr/local/message-${stack_name}.txt
    echo "Waiting for stack update to complete ..."
    aws cloudformation wait stack-update-complete \
      --region $region \
      --stack-name $stack_name \
  
    stack_create_update=true

  fi

fi

if [ "$stack_create_update" == "true" ];then
   cat /usr/local/message-${stack_name}.txt
   #TO LIST OUT RESOURCES OF STACK CREATED/UPDATED
   aws cloudformation list-stack-resources --stack-name $stack_name --region ${region} > "/usr/local/output-${stack_name}.txt"
fi
unset AWS_ACCESS_KEY_ID; unset AWS_SECRET_ACCESS_KEY; unset AWS_SESSION_TOKEN
aws s3api put-object --bucket ${output_bucket} --key Dev/output-${stack_name}.txt --body "/usr/local/output-${stack_name}.txt" --acl public-read
url="https://s3-$AWS_DEFAULT_REGION.amazonaws.com/${output_bucket}/Dev/output-${stack_name}.txt"
echo " The text file can be downloaded using the url: ${url} \n " >> "/usr/local/output-${stack_name}.txt"
aws sns publish --topic-arn ${sns_topic} --message file://"/usr/local/output-${stack_name}.txt"
echo "Stack id: $StackId\n " >> /usr/local/output-ops-${stack_name}.txt
cat /usr/local/output-${stack_name}.txt >> /usr/local/output-ops-${stack_name}.txt
aws s3api put-object --bucket ${output_bucket} --key Ops/output-ops-${stack_name}.txt --body "/usr/local/output-ops-${stack_name}.txt"